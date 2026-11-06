using System.Text.Json;

// z2roN_Store 서버: MDB를 소유하고 같은 네트워크의 PC/모바일에 API를 제공한다.
const string Version = "0.2.0";
var cfgPath = Path.Combine(AppContext.BaseDirectory, "server.json");
if (!File.Exists(cfgPath))
    File.WriteAllText(cfgPath, "{\n  \"port\": 5080,\n  \"mdbPath\": \"data\\\\store.mdb\",\n  \"provider\": \"Microsoft.Jet.OLEDB.4.0\",\n  \"backupDir\": \"backup\",\n  \"backupKeep\": 30\n}");
var cfg = JsonDocument.Parse(File.ReadAllText(cfgPath)).RootElement;
int port = cfg.TryGetProperty("port", out var pp) ? pp.GetInt32() : 5080;
string mdb = cfg.TryGetProperty("mdbPath", out var mp) ? mp.GetString()! : "data\\store.mdb";
if (!Path.IsPathRooted(mdb)) mdb = Path.Combine(AppContext.BaseDirectory, mdb);
string provider = cfg.TryGetProperty("provider", out var pv) ? pv.GetString() : null;
string backupDir = cfg.TryGetProperty("backupDir", out var bd) ? bd.GetString()! : "backup";
if (!Path.IsPathRooted(backupDir)) backupDir = Path.Combine(AppContext.BaseDirectory, backupDir);
int keep = cfg.TryGetProperty("backupKeep", out var bk) ? bk.GetInt32() : 30;

Console.WriteLine($"z2roN_Store 서버 v{Version}");
Console.WriteLine($"MDB: {mdb}");
Db.Init(mdb, provider);
Backup.Start(mdb, backupDir, keep);

var builder = WebApplication.CreateBuilder();
builder.WebHost.UseUrls($"http://0.0.0.0:{port}");
builder.WebHost.ConfigureKestrel(o => o.Limits.MaxRequestBodySize = 300_000_000);
builder.Logging.SetMinimumLevel(LogLevel.Warning);
builder.Services.ConfigureHttpJsonOptions(o => o.SerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.CamelCase);
var app = builder.Build();

// 인증: /api/ping, /api/login 외에는 토큰 필요
app.Use(async (ctx, next) =>
{
    var p = ctx.Request.Path.Value ?? "";
    if (p.StartsWith("/api") && p != "/api/ping" && p != "/api/login" && Auth.Get(ctx) == null)
    { ctx.Response.StatusCode = 401; await ctx.Response.WriteAsJsonAsync(new { error = "로그인이 필요합니다" }); return; }
    try { await next(); }
    catch (Exception e)
    { ctx.Response.StatusCode = 500; await ctx.Response.WriteAsJsonAsync(new { error = e.Message }); }
});

app.MapGet("/api/ping", () => new { app = "z2roN_Store", version = Version, store = Setting("storeName", "매장"), time = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") });
app.MapPost("/api/login", (LoginReq r) => Auth.Login(r.User, r.Pin) is { } ok ? Results.Json(ok) : Results.Json(new { error = "아이디 또는 비밀번호가 올바르지 않습니다" }, statusCode: 401));

// ---------- 상품 (ProductApi.cs) ----------
app.MapProducts();

// ---------- 재고 ----------
app.MapPost("/api/stock/adjust", (HttpContext c, AdjustReq a) =>
{
    var u = Auth.Get(c);
    Db.Tx(t =>
    {
        t.Exec("UPDATE Products SET Stock = Stock + ? WHERE Id=?", a.Delta, a.ProductId);
        t.Exec("INSERT INTO StockMoves (MoveDate,ProductId,Delta,Reason,RefId,UserName,Memo) VALUES (?,?,?,?,?,?,?)", DateTime.Now, a.ProductId, a.Delta, a.Reason ?? "조정", 0, u.Name, a.Memo ?? "");
        return 0;
    });
    return Results.Json(new { ok = true });
});
app.MapGet("/api/stock/moves", (int? productId) =>
    productId is int pid
        ? Db.Query("SELECT m.*, p.Name FROM StockMoves m LEFT JOIN Products p ON m.ProductId=p.Id WHERE m.ProductId=? ORDER BY m.Id DESC", pid)
        : Db.Query("SELECT TOP 200 m.*, p.Name FROM StockMoves m LEFT JOIN Products p ON m.ProductId=p.Id ORDER BY m.Id DESC"));
app.MapGet("/api/stock/low", () => ProductApi.AttachUnits(Db.Query("SELECT TOP 500 * FROM Products WHERE Active=True AND (Discontinued IS NULL OR Discontinued=False) AND MinStock > 0 AND Stock <= MinStock ORDER BY Name")));

// ---------- 고객 / 거래처 ----------
app.MapGet("/api/customers", (string q) =>
{
    q = (q ?? "").Trim();
    return q == "" ? Db.Query("SELECT * FROM Customers WHERE Active=True ORDER BY Name")
        : Db.Query("SELECT * FROM Customers WHERE Active=True AND (Name LIKE ? OR Phone LIKE ?) ORDER BY Name", "%" + q + "%", "%" + q + "%");
});
app.MapPost("/api/customers", (CustomerReq r) =>
{
    if (string.IsNullOrWhiteSpace(r.Name)) return Results.Json(new { error = "이름을 입력하세요" }, statusCode: 400);
    if (r.Id == 0)
    {
        int id = Db.Tx(t => t.Insert("INSERT INTO Customers (Name,Phone,Address,Balance,Memo,Active,Kind,PriceTier) VALUES (?,?,?,?,?,?,?,?)", r.Name, r.Phone ?? "", r.Address ?? "", 0, r.Memo ?? "", true, r.Kind ?? "개인", Math.Clamp(r.PriceTier, 1, 10)));
        return Results.Json(new { id });
    }
    Db.Exec("UPDATE Customers SET Name=?,Phone=?,Address=?,Memo=?,Kind=?,PriceTier=? WHERE Id=?", r.Name, r.Phone ?? "", r.Address ?? "", r.Memo ?? "", r.Kind ?? "개인", Math.Clamp(r.PriceTier, 1, 10), r.Id);
    return Results.Json(new { id = r.Id });
});
app.MapDelete("/api/customers/{id:int}", (int id) => { Db.Exec("UPDATE Customers SET Active=False WHERE Id=?", id); return Results.Json(new { ok = true }); });
app.MapPost("/api/customers/{id:int}/payment", (int id, PayReq r) =>
{ Db.Exec("UPDATE Customers SET Balance = Balance - ? WHERE Id=?", r.Amount, id); return Results.Json(new { ok = true }); });

app.MapGet("/api/vendors", () => Db.Query("SELECT * FROM Vendors WHERE Active=True ORDER BY Name"));
app.MapPost("/api/vendors", (VendorReq r) =>
{
    if (string.IsNullOrWhiteSpace(r.Name)) return Results.Json(new { error = "업체명을 입력하세요" }, statusCode: 400);
    if (r.Id == 0)
    {
        int id = Db.Tx(t => t.Insert("INSERT INTO Vendors (Name,Phone,BizNo,Address,Memo,Active) VALUES (?,?,?,?,?,?)", r.Name, r.Phone ?? "", r.BizNo ?? "", r.Address ?? "", r.Memo ?? "", true));
        return Results.Json(new { id });
    }
    Db.Exec("UPDATE Vendors SET Name=?,Phone=?,BizNo=?,Address=?,Memo=? WHERE Id=?", r.Name, r.Phone ?? "", r.BizNo ?? "", r.Address ?? "", r.Memo ?? "", r.Id);
    return Results.Json(new { id = r.Id });
});

// ---------- 판매 ----------
app.MapPost("/api/sales", (HttpContext c, SaleReq s) =>
{
    var u = Auth.Get(c);
    if (s.Items == null || s.Items.Count == 0) return Results.Json(new { error = "판매 품목이 없습니다" }, statusCode: 400);
    long sum = s.Items.Sum(i => (long)i.Qty * i.Price);
    long total = Math.Max(0, sum - s.Discount);
    long paid = s.PayMethod == "외상" ? s.Paid : (s.Paid > 0 ? s.Paid : total);
    if (s.PayMethod == "외상" && s.CustomerId == 0) return Results.Json(new { error = "외상 판매는 고객을 선택해야 합니다" }, statusCode: 400);
    var now = DateTime.Now;
    var res = Db.Tx(t =>
    {
        int seq = Convert.ToInt32(t.Scalar("SELECT COUNT(*) FROM Sales WHERE SaleDate >= ? AND SaleDate < ?", now.Date, now.Date.AddDays(1)) ?? 0) + 1;
        string no = now.ToString("yyyyMMdd") + "-" + seq.ToString("D4");
        int sid = t.Insert("INSERT INTO Sales (SaleNo,SaleDate,CustomerId,UserName,Total,Discount,Paid,PayMethod,Cancelled,Memo) VALUES (?,?,?,?,?,?,?,?,?,?)",
            no, now, s.CustomerId, u.Name, (int)total, s.Discount, (int)paid, s.PayMethod ?? "현금", false, s.Memo ?? "");
        foreach (var i in s.Items)
        {
            int uq = Math.Max(1, i.UnitQty);
            t.Exec("INSERT INTO SaleItems (SaleId,ProductId,Name,Qty,Price,Amount,UnitName,UnitQty) VALUES (?,?,?,?,?,?,?,?)", sid, i.ProductId, i.Name ?? "", i.Qty, i.Price, i.Qty * i.Price, i.UnitName ?? "", uq);
            if (i.ProductId > 0)
            {
                t.Exec("UPDATE Products SET Stock = Stock - ? WHERE Id=?", i.Qty * uq, i.ProductId);
                t.Exec("INSERT INTO StockMoves (MoveDate,ProductId,Delta,Reason,RefId,UserName,Memo) VALUES (?,?,?,?,?,?,?)", now, i.ProductId, -(i.Qty * uq), "판매", sid, u.Name, no);
            }
        }
        if (s.CustomerId > 0 && total - paid != 0) t.Exec("UPDATE Customers SET Balance = Balance + ? WHERE Id=?", (int)(total - paid), s.CustomerId);
        return new { id = sid, saleNo = no, total, paid };
    });
    return Results.Json(res);
});
app.MapGet("/api/sales", (string from, string to, int? customerId) =>
{
    var f = DateTime.TryParse(from, out var fd) ? fd.Date : DateTime.Today;
    var e = (DateTime.TryParse(to, out var td) ? td.Date : DateTime.Today).AddDays(1);
    var sql = "SELECT s.*, c.Name AS CustomerName FROM Sales s LEFT JOIN Customers c ON s.CustomerId=c.Id WHERE s.SaleDate >= ? AND s.SaleDate < ?";
    var a = new List<object> { f, e };
    if (customerId is int cid && cid > 0) { sql += " AND s.CustomerId=?"; a.Add(cid); }
    return Db.Query(sql + " ORDER BY s.Id DESC", a.ToArray());
});
app.MapGet("/api/sales/{id:int}", (int id) =>
{
    var h = Db.Query("SELECT s.*, c.Name AS CustomerName FROM Sales s LEFT JOIN Customers c ON s.CustomerId=c.Id WHERE s.Id=?", id);
    if (h.Count == 0) return Results.Json(new { error = "없는 판매입니다" }, statusCode: 404);
    return Results.Json(new { sale = h[0], items = Db.Query("SELECT * FROM SaleItems WHERE SaleId=?", id) });
});
app.MapPost("/api/sales/{id:int}/cancel", (HttpContext c, int id) =>
{
    var u = Auth.Get(c);
    Db.Tx(t =>
    {
        var already = t.Scalar("SELECT Cancelled FROM Sales WHERE Id=?", id);
        if (already is bool b && b) throw new Exception("이미 취소된 판매입니다");
        var cid = Convert.ToInt32(t.Scalar("SELECT CustomerId FROM Sales WHERE Id=?", id) ?? 0);
        var total = Convert.ToInt32(t.Scalar("SELECT Total FROM Sales WHERE Id=?", id) ?? 0);
        var paid = Convert.ToInt32(t.Scalar("SELECT Paid FROM Sales WHERE Id=?", id) ?? 0);
        t.Exec("UPDATE Sales SET Cancelled=True WHERE Id=?", id);
        // 상품별 재고 복구
        foreach (var it in t.Query("SELECT ProductId, Qty, UnitQty FROM SaleItems WHERE SaleId=? AND ProductId>0", id))
        {
            int pid = Convert.ToInt32(it["ProductId"]), uq0 = it["UnitQty"] == null ? 1 : Math.Max(1, Convert.ToInt32(it["UnitQty"])), qty = Convert.ToInt32(it["Qty"]) * uq0;
            t.Exec("UPDATE Products SET Stock = Stock + ? WHERE Id=?", qty, pid);
            t.Exec("INSERT INTO StockMoves (MoveDate,ProductId,Delta,Reason,RefId,UserName,Memo) VALUES (?,?,?,?,?,?,?)", DateTime.Now, pid, qty, "판매취소", id, u.Name, "");
        }
        if (cid > 0 && total - paid != 0) t.Exec("UPDATE Customers SET Balance = Balance - ? WHERE Id=?", total - paid, cid);
        return 0;
    });
    return Results.Json(new { ok = true });
});

// ---------- 설정 / 사용자 / 요약 ----------
app.MapGet("/api/settings", () => Db.Query("SELECT K,V FROM Settings").ToDictionary(r => (string)r["K"], r => r["V"]));
app.MapPost("/api/settings", (Dictionary<string, string> kv) =>
{
    foreach (var (k, v) in kv)
        if (Db.Exec("UPDATE Settings SET V=? WHERE K=?", v ?? "", k) == 0) Db.Exec("INSERT INTO Settings (K,V) VALUES (?,?)", k, v ?? "");
    return Results.Json(new { ok = true });
});
app.MapGet("/api/users", (HttpContext c) => Auth.Get(c).Role == "admin" ? Results.Json(Db.Query("SELECT Id,LoginName,DisplayName,Role,Active FROM Users ORDER BY Id")) : Results.Json(new { error = "권한이 없습니다" }, statusCode: 403));
app.MapPost("/api/users", (HttpContext c, UserReq r) =>
{
    if (Auth.Get(c).Role != "admin") return Results.Json(new { error = "권한이 없습니다" }, statusCode: 403);
    if (r.Id == 0) Db.Exec("INSERT INTO Users (LoginName,Pin,DisplayName,Role,Active) VALUES (?,?,?,?,?)", r.LoginName, Auth.Hash(r.Pin ?? "0000"), r.DisplayName, r.Role ?? "staff", true);
    else
    {
        Db.Exec("UPDATE Users SET DisplayName=?,Role=?,Active=? WHERE Id=?", r.DisplayName, r.Role ?? "staff", r.Active ?? true, r.Id);
        if (!string.IsNullOrEmpty(r.Pin)) Db.Exec("UPDATE Users SET Pin=? WHERE Id=?", Auth.Hash(r.Pin), r.Id);
    }
    return Results.Json(new { ok = true });
});
app.MapGet("/api/report/summary", (string date) =>
{
    var d = DateTime.TryParse(date, out var x) ? x.Date : DateTime.Today;
    var rows = Db.Query("SELECT PayMethod, COUNT(*) AS Cnt, SUM(Total) AS Total, SUM(Paid) AS Paid FROM Sales WHERE Cancelled=False AND SaleDate >= ? AND SaleDate < ? GROUP BY PayMethod", d, d.AddDays(1));
    return Results.Json(new { date = d.ToString("yyyy-MM-dd"), byMethod = rows });
});

Console.WriteLine($"실행 중: http://0.0.0.0:{port}  (이 창을 닫으면 서버가 종료됩니다)");
app.Run();

static string Setting(string k, string def)
{ try { var r = Db.Query("SELECT V FROM Settings WHERE K=?", k); return r.Count > 0 ? (string)r[0]["V"] : def; } catch { return def; } }

record LoginReq(string User, string Pin);
record AdjustReq(int ProductId, int Delta, string Reason, string Memo);
record CustomerReq(int Id, string Name, string Phone, string Address, string Memo, string Kind, int PriceTier);
record VendorReq(int Id, string Name, string Phone, string BizNo, string Address, string Memo);
record PayReq(int Amount);
record SaleItemReq(int ProductId, string Name, int Qty, int Price, string UnitName, int UnitQty);
record SaleReq(int CustomerId, List<SaleItemReq> Items, int Discount, int Paid, string PayMethod, string Memo);
record UserReq(int Id, string LoginName, string Pin, string DisplayName, string Role, bool? Active);
