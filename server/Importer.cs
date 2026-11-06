using System.Globalization;
using System.Text;
using ExcelDataReader;

// BMIT 형식 상품 엑셀 가져오기: 묶음코드가 같은 행 중 입수가 더 큰 행은 2차 단위(갑/타/박스)로 붙인다.
public static class Importer
{
    public static bool Running;
    public static int Total, Done, Added, Skipped, DupBarcodes, NewVendors;
    public static string Message = "", Error = "";

    public static object StatusObj() => new { running = Running, total = Total, done = Done, added = Added, skipped = Skipped, dupBarcodes = DupBarcodes, newVendors = NewVendors, message = Message, error = Error };

    public static bool Start(byte[] data, string fileName)
    {
        lock (typeof(Importer))
        {
            if (Running) return false;
            Running = true; Total = Done = Added = Skipped = DupBarcodes = NewVendors = 0; Message = "파일 읽는 중..."; Error = "";
        }
        Task.Run(() =>
        {
            try { Run(data, fileName); Message = "완료"; }
            catch (Exception e) { Error = e.Message; Message = "실패"; Console.WriteLine("가져오기 실패: " + e); }
            finally { Running = false; }
        });
        return true;
    }

    static string Str(object v)
    {
        if (v == null) return "";
        if (v is double d) return d == Math.Floor(d) && Math.Abs(d) < 1e15 ? ((long)d).ToString(CultureInfo.InvariantCulture) : d.ToString("R", CultureInfo.InvariantCulture);
        return Convert.ToString(v, CultureInfo.InvariantCulture)?.Trim() ?? "";
    }

    static List<Dictionary<string, string>> ReadRows(byte[] data, string fileName)
    {
        Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
        using var ms = new MemoryStream(data);
        var cfg = new ExcelReaderConfiguration { FallbackEncoding = Encoding.GetEncoding(949) };
        using IExcelDataReader r = fileName.EndsWith(".csv", StringComparison.OrdinalIgnoreCase)
            ? ExcelReaderFactory.CreateCsvReader(ms, cfg) : ExcelReaderFactory.CreateReader(ms, cfg);
        var rows = new List<Dictionary<string, string>>();
        do
        {
            string[] head = null;
            while (r.Read())
            {
                if (head == null)
                {
                    head = new string[r.FieldCount];
                    for (int i = 0; i < head.Length; i++) head[i] = Str(r.GetValue(i));
                    if (!head.Contains("상품명")) break; // 상품 목록 시트가 아님
                    continue;
                }
                var d = new Dictionary<string, string>();
                for (int i = 0; i < Math.Min(head.Length, r.FieldCount); i++) if (head[i] != "") d[head[i]] = Str(r.GetValue(i));
                if (d.TryGetValue("상품명", out var nm) && nm != "") rows.Add(d);
            }
        } while (r.NextResult());
        return rows;
    }

    static string G(Dictionary<string, string> d, string k) => d.TryGetValue(k, out var v) ? v : "";
    static int I(Dictionary<string, string> d, string k)
    {
        var s = G(d, k).Replace(",", "");
        return double.TryParse(s, NumberStyles.Any, CultureInfo.InvariantCulture, out var x) ? (int)Math.Round(x) : 0;
    }
    static string Unit(string s)
    {
        s = (s ?? "").Trim();
        if (s == "" || s.All(char.IsDigit) || s.Equals("EA", StringComparison.OrdinalIgnoreCase)) return "개";
        return s;
    }

    class Spec { public Dictionary<string, string> Main; public List<Dictionary<string, string>> Others = new(); }

    static void Run(byte[] data, string fileName)
    {
        var rows = ReadRows(data, fileName);
        if (rows.Count == 0) throw new Exception("상품 행을 찾지 못했습니다. '상품명' 헤더가 있는 시트인지 확인하세요.");
        Message = "분석 중...";
        const string K1 = "기준코드(수정불가)", K2 = "묶음코드(수정불가)";
        var groups = new List<List<Dictionary<string, string>>>(); var gi = new Dictionary<string, int>();
        int n = 0;
        foreach (var r in rows)
        {
            n++;
            var key = G(r, K2) != "" ? G(r, K2) : (G(r, K1) != "" ? G(r, K1) : "row" + n);
            if (!gi.TryGetValue(key, out var ix)) { ix = groups.Count; gi[key] = ix; groups.Add(new()); }
            groups[ix].Add(r);
        }
        var specs = new List<Spec>();
        foreach (var g in groups)
        {
            int minq = g.Min(x => Math.Max(1, I(x, "낱개")));
            var bases = g.Where(x => Math.Max(1, I(x, "낱개")) == minq).ToList();
            var main = new Spec { Main = bases[0] };
            main.Others.AddRange(g.Where(x => Math.Max(1, I(x, "낱개")) > minq));
            specs.Add(main);
            for (int i = 1; i < bases.Count; i++) specs.Add(new Spec { Main = bases[i] }); // 입수가 같은 다른 행은 별도 상품
        }
        Total = specs.Count;

        var legacy = new HashSet<string>(Db.Query("SELECT LegacyId FROM Products WHERE LegacyId IS NOT NULL").Select(x => Convert.ToString(x["LegacyId"])));
        var barcodes = new HashSet<string>(Db.Query("SELECT Barcode FROM ProductUnits").Select(x => Convert.ToString(x["Barcode"]) ?? ""));
        var vendors = new Dictionary<string, int>();
        foreach (var v in Db.Query("SELECT Id, BizNo FROM Vendors")) { var b = Convert.ToString(v["BizNo"]) ?? ""; if (b != "") vendors[b] = Convert.ToInt32(v["Id"]); }

        Message = "등록 중...";
        const int Batch = 300;
        for (int s = 0; s < specs.Count; s += Batch)
        {
            var batch = specs.Skip(s).Take(Batch).ToList();
            Db.Tx(t =>
            {
                foreach (var sp in batch)
                {
                    var b = sp.Main; var lid = G(b, K1);
                    if (lid != "" && legacy.Contains(lid)) { Skipped++; continue; }
                    int baseQty = Math.Max(1, I(b, "낱개"));
                    int vid = 0; var biz = G(b, "매입사");
                    if (biz != "" && !vendors.TryGetValue(biz, out vid))
                    {
                        vid = t.InsertRow("Vendors", ("Name", ProductApi.S(biz, 60)), ("Phone", ""), ("BizNo", ProductApi.S(biz, 20)), ("Address", ""), ("Memo", "가져오기로 자동 등록"), ("Active", true));
                        vendors[biz] = vid; NewVendors++;
                    }
                    var bu = Unit(G(b, "단위"));
                    int pid = t.InsertRow("Products",
                        ("Barcode", ProductApi.S(G(b, "바코드"), 40)), ("Name", ProductApi.S(G(b, "상품명"), 100)), ("ShareName", ProductApi.S(G(b, "공유상품명"), 100)),
                        ("Spec", ProductApi.S(G(b, "규격"), 60)), ("Category", ProductApi.S(G(b, "분류"), 40)), ("Kind", I(b, "상품구분")),
                        ("BaseUnit", ProductApi.S(bu, 20)), ("Maker", ProductApi.S(G(b, "제조사"), 60)), ("Origin", ProductApi.S(G(b, "원산지"), 40)),
                        ("ItemNo", ProductApi.S(G(b, "품번"), 60)), ("ItemNo2", ProductApi.S(G(b, "품번2"), 60)), ("ItemNo3", ProductApi.S(G(b, "품번3"), 60)),
                        ("ItemNo4", ProductApi.S(G(b, "품번4"), 60)), ("BookCode", ProductApi.S(G(b, "책자코드"), 40)), ("Shelf", ProductApi.S(G(b, "매대"), 40)),
                        ("Location", ProductApi.S(G(b, "위치"), 40)), ("Keywords", ProductApi.S(G(b, "키워드"), 100)), ("Memo", ProductApi.S(G(b, "비고"), 200)),
                        ("VendorId", vid), ("MinStock", 0), ("Stock", 0), ("CostDC", I(b, "매입DC")), ("Cost", I(b, "매입단가")), ("Price", I(b, "판매가 1")),
                        ("NoPoint", G(b, "적립제외") == "Y"), ("TaxFree", G(b, "면세") == "Y"), ("Discontinued", G(b, "단종") == "Y"),
                        ("NoReturn", G(b, "반품불가") == "Y"), ("NoDiscount", G(b, "할인제외") == "Y"),
                        ("LegacyId", ProductApi.S(lid, 30)), ("GroupId", ProductApi.S(G(b, K2), 30)), ("Active", true));
                    var all = new List<(Dictionary<string, string> row, int qty, bool isBase)> { (b, 1, true) };
                    foreach (var o in sp.Others) all.Add((o, Math.Max(1, (int)Math.Round(Math.Max(1, I(o, "낱개")) / (double)baseQty)), false));
                    foreach (var (row, qty, isBase) in all)
                    {
                        var bc = ProductApi.S(G(row, "바코드"), 40);
                        if (bc != "" && !barcodes.Add(bc)) { DupBarcodes++; bc = ""; }
                        var pr = new int[10]; for (int i = 0; i < 10; i++) pr[i] = I(row, "판매가 " + (i + 1));
                        t.InsertRow("ProductUnits", ProductApi.UnitCols(pid, new UnitReq { UnitName = isBase ? bu : Unit(G(row, "단위")), Qty = qty, Barcode = bc, Cost = I(row, "매입단가"), Retail = I(row, "소비자가"), Prices = pr }, isBase));
                    }
                    if (lid != "") legacy.Add(lid);
                    Added++;
                }
                return 0;
            });
            Done = Math.Min(s + Batch, specs.Count);
        }
        Done = Total;
    }
}
