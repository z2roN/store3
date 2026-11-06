// MDB 자동 백업: 시작 시 + 매일 새벽 3시, 보관 개수 초과분 삭제
public static class Backup
{
    public static void Start(string mdb, string dir, int keep)
    {
        Directory.CreateDirectory(dir);
        void Run()
        {
            try
            {
                var dst = Path.Combine(dir, "store_" + DateTime.Now.ToString("yyyyMMdd_HHmmss") + ".mdb");
                File.Copy(mdb, dst, true);
                foreach (var f in new DirectoryInfo(dir).GetFiles("store_*.mdb").OrderByDescending(x => x.Name).Skip(keep)) f.Delete();
                Console.WriteLine("백업 완료: " + dst);
            }
            catch (Exception e) { Console.WriteLine("백업 실패: " + e.Message); }
        }
        Run();
        new Thread(() =>
        {
            while (true)
            {
                var next = DateTime.Today.AddHours(3); if (next <= DateTime.Now) next = next.AddDays(1);
                Thread.Sleep(next - DateTime.Now);
                Run();
            }
        }) { IsBackground = true }.Start();
    }
}
