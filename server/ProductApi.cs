// 상품(기준 단위 + 갑/박스 등 2차 단위·바코드) API
public class UnitReq
{
    public string UnitName { get; set; }
    public int Qty { get; set; } = 1;       // 입수(기준 단위 몇 개)
    public string Barcode { get; set; }
    public int Cost { get; set; }
    public int Retail { get; set; }          // 소비자가
    public int[] Prices { get; set; }        // 판매가 1~10 (0 = 자동)
}

public class ProductReq
{
    public int Id { get; set; }
    public string Name { get; set; }
    public string ShareName { get; set; }
    public string Spec { get; set; }
    public string Category { get; set; }
    public int Kind { get; set; }
    public string Maker { get; set; }
    public string Origin { get; set; }
    public string ItemNo { get; set; }
    public string ItemNo2 { get; set; }
    public string ItemNo3 { get; set; }
    public string ItemNo4 { get; set; }
    public string BookCode { get; set; }
    public string Shelf { get; set; }
    public string Location { get; set; }
    public string Keywords { get; set; }
    public string Memo { get; set; }
    public int VendorId { get; set; }
    public int MinStock { get; set; }
    public int Stock { get; set; }           // 새 상품의 처음 재고(기준 단위)
    public int CostDC { get; set; }
    public bool NoPoint { get; set; }
    public bool TaxFree { get; set; }
    public bool Discontinued { get; set; }
    public bool NoReturn { get; set; }
    public bool NoDiscount { get; set; }
    public bool? Active { get; set; }
    public List<UnitReq> Units { get; set; }
}

public static class ProductApi
{
    public static string S(string s, int n) { s = (s ?? "").Trim(); return s.Length > n ? s.Substring(0, n) : s; }

    public static List<Dictionary<string, object>> AttachUnits(List<Dictionary<string, object>> ps)
    {
        if (ps.Count == 0) return ps;
        var ids = string.Join(",", ps.Select(p => Convert.ToInt32(p["Id"])));
        var us = Db.Query($"SELECT * FROM ProductUnits WHERE ProductId IN ({ids}) ORDER BY Qty, Id");
        var by = us.GroupBy(u => Convert.ToInt32(u["ProductId"])).ToDictionary(g => g.Key, g => g.ToList());
        foreach (var p in ps) p["Units"] = by.TryGetValue(Convert.ToInt32(p["Id"]), out var l) ? l : new List<Dictionary<string, object>>();
        return ps;
    }

    public static (string, object)[] UnitCols(int pid, UnitReq u, bool isBase)
    {
        var pr = u.Prices ?? new int[10];
        var l = new List<(string, object)>
        {
            ("ProductId", pid), ("UnitName", S(u.UnitName, 20)), ("Qty", Math.Max(1, u.Qty)), ("Barcode", S(u.Barcode, 40)),
            ("Cost", u.Cost), ("Retail", u.Retail), ("IsBase", isBase),
        };
        for (int i = 0; i < 10; i++) l.Add(("Price" + (i + 1), i < pr.Length ? pr[i] : 0));
        return l.ToArray();
    }

    static (string, object)[] ProdCols(ProductReq p, UnitReq b) => new (string, object)[]
    {
        ("Barcode", S(b.Barcode, 40)), ("Name", S(p.Name, 100)), ("ShareName", S(p.ShareName, 100)), ("Spec", S(p.Spec, 60)),
        ("Category", S(p.Category, 40)), ("Kind", p.Kind), ("BaseUnit", S(b.UnitName, 20)), ("Maker", S(p.Maker, 60)),
        ("Origin", S(p.Origin, 40)), ("ItemNo", S(p.ItemNo, 60)), ("ItemNo2", S(p.ItemNo2, 60)), ("ItemNo3", S(p.ItemNo3, 60)),
        ("ItemNo4", S(p.ItemNo4, 60)), ("BookCode", S(p.BookCode, 40)), ("Shelf", S(p.Shelf, 40)), ("Location", S(p.Location, 40)),
        ("Keywords", S(p.Keywords, 100)), ("Memo", S(p.Memo, 200)), ("VendorId", p.VendorId), ("MinStock", p.MinStock),
        ("CostDC", p.CostDC), ("Cost", b.Cost), ("Price", (b.Prices != null && b.Prices.Length > 0) ? b.Prices[0] : 0),
        ("NoPoint", p.NoPoint), ("TaxFree", p.TaxFree), ("Discontinued", p.Discontinued), ("NoReturn", p.NoReturn), ("NoDiscount", p.NoDiscount),
    };

    public static void MapProducts(this WebApplication app)
    {
        app.MapGet("/api/products", (string q, bool? disc, int? limit) =>
        {
            int lim = Math.Clamp(limit ?? 200, 1, 1000);
            var sql = $"SELECT TOP {lim} * FROM Products WHERE Active=True";
            var a = new List<object>();
            if (disc != true) sql += " AND (Discontinued IS NULL OR Discontinued=False)";
            q = (q ?? "").Trim();
            if (q != "")
            {
                sql += " AND (Name LIKE ? OR ShareName LIKE ? OR Category LIKE ? OR ItemNo LIKE ? OR Id IN (SELECT ProductId FROM ProductUnits WHERE Barcode LIKE ?))";
                var like = "%" + q + "%";
                a.AddRange(new object[] { like, like, like, like, like });
            }
            return AttachUnits(Db.Query(sql + " ORDER BY Name", a.ToArray()));
        });

        app.MapGet("/api/products/count", () => new { total = Db.Scalar("SELECT COUNT(*) FROM Products WHERE Active=True") });

        app.MapGet("/api/products/barcode/{code}", (string code) =>
        {
            var r = Db.Query("SELECT p.*, u.Id AS ScanUnitId FROM Products p INNER JOIN ProductUnits u ON p.Id=u.ProductId WHERE u.Barcode=? AND p.Active=True", code);
            return r.Count > 0 ? Results.Json(AttachUnits(r)[0]) : Results.Json(new { error = "등록되지 않은 바코드입니다" }, statusCode: 404);
        });

        app.MapPost("/api/products", (HttpContext c, ProductReq p) =>
        {
            var u = Auth.Get(c);
            if (string.IsNullOrWhiteSpace(p.Name)) return Results.Json(new { error = "상품명을 입력하세요" }, statusCode: 400);
            if (p.Units == null || p.Units.Count == 0) return Results.Json(new { error = "기준 단위를 하나 이상 입력하세요" }, statusCode: 400);
            p.Units[0].Qty = 1; // 첫 줄이 기준(낱개) 단위
            var seen = new HashSet<string>();
            foreach (var un in p.Units)
            {
                if (string.IsNullOrWhiteSpace(un.UnitName)) return Results.Json(new { error = "단위 이름을 입력하세요" }, statusCode: 400);
                var bc = S(un.Barcode, 40);
                if (bc == "") continue;
                if (!seen.Add(bc)) return Results.Json(new { error = $"같은 바코드가 두 번 입력되었습니다: {bc}" }, statusCode: 400);
                var dup = Db.Query("SELECT p.Name FROM ProductUnits u INNER JOIN Products p ON p.Id=u.ProductId WHERE u.Barcode=? AND u.ProductId<>? AND p.Active=True", bc, p.Id);
                if (dup.Count > 0) return Results.Json(new { error = $"바코드 {bc} 는 이미 '{dup[0]["Name"]}' 상품에서 사용 중입니다" }, statusCode: 400);
            }
            var b = p.Units[0];
            int id = Db.Tx(t =>
            {
                int pid = p.Id;
                if (pid == 0)
                {
                    var cols = ProdCols(p, b).Concat(new (string, object)[] { ("Active", true), ("Stock", p.Stock) }).ToArray();
                    pid = t.InsertRow("Products", cols);
                    if (p.Stock != 0) t.Exec("INSERT INTO StockMoves (MoveDate,ProductId,Delta,Reason,RefId,UserName,Memo) VALUES (?,?,?,?,?,?,?)", DateTime.Now, pid, p.Stock, "초기", 0, u.Name, "상품 등록");
                }
                else
                {
                    t.UpdateRow("Products", pid, ProdCols(p, b).Concat(new (string, object)[] { ("Active", p.Active ?? true) }).ToArray());
                    t.Exec("DELETE FROM ProductUnits WHERE ProductId=?", pid);
                }
                for (int i = 0; i < p.Units.Count; i++) t.InsertRow("ProductUnits", UnitCols(pid, p.Units[i], i == 0));
                return pid;
            });
            return Results.Json(new { id });
        });

        app.MapDelete("/api/products/{id:int}", (int id) => { Db.Exec("UPDATE Products SET Active=False WHERE Id=?", id); return Results.Json(new { ok = true }); });

        // 엑셀(.xls/.xlsx/.csv) 일괄 등록: 본문에 파일 원본, ?name=파일이름
        app.MapPost("/api/products/import", async (HttpContext c, string name) =>
        {
            if (Auth.Get(c).Role != "admin") return Results.Json(new { error = "관리자만 가능합니다" }, statusCode: 403);
            using var ms = new MemoryStream();
            await c.Request.Body.CopyToAsync(ms);
            if (ms.Length < 100) return Results.Json(new { error = "파일이 비어 있습니다" }, statusCode: 400);
            return Importer.Start(ms.ToArray(), name ?? "x.xlsx") ? Results.Json(new { ok = true }) : Results.Json(new { error = "이미 가져오기가 진행 중입니다" }, statusCode: 409);
        });
        app.MapGet("/api/products/import/status", () => Importer.StatusObj());
    }
}
