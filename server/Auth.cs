using System.Collections.Concurrent;
using System.Security.Cryptography;
using System.Text;

public static class Auth
{
    public record Session(string User, string Name, string Role, DateTime Expires);
    static readonly ConcurrentDictionary<string, Session> Sessions = new();

    public static string Hash(string pin) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes("z2roN-store:" + pin)));

    public static object Login(string user, string pin)
    {
        var rows = Db.Query("SELECT DisplayName, Role FROM Users WHERE LoginName=? AND Pin=? AND Active=True", user ?? "", Hash(pin ?? ""));
        if (rows.Count == 0) return null;
        var token = Convert.ToHexString(RandomNumberGenerator.GetBytes(24));
        var name = (string)rows[0]["DisplayName"]; var role = (string)rows[0]["Role"];
        Sessions[token] = new Session(user, name, role, DateTime.Now.AddHours(12));
        return new { token, name, role };
    }

    public static Session Get(HttpContext ctx)
    {
        var h = ctx.Request.Headers["X-Token"].ToString();
        if (h != "" && Sessions.TryGetValue(h, out var s) && s.Expires > DateTime.Now) return s;
        return null;
    }
}
