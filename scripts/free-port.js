/**
 * 지정한 포트를 점유 중인 프로세스를 종료한다. (Windows / macOS / Linux 공용)
 * 사용법: node scripts/free-port.js 5001
 */
const { execSync } = require("child_process");

const port = process.argv[2] || "5001";
const isWin = process.platform === "win32";

function pids() {
  try {
    if (isWin) {
      const out = execSync(`netstat -ano -p tcp`, { encoding: "utf8" });
      return [
        ...new Set(
          out
            .split(/\r?\n/)
            .filter((l) => /LISTENING/i.test(l) && new RegExp(`[:.]${port}\s`).test(l))
            .map((l) => l.trim().split(/\s+/).pop())
            .filter((p) => p && p !== "0")
        ),
      ];
    }
    const out = execSync(`lsof -ti tcp:${port}`, { encoding: "utf8" });
    return out.split(/\s+/).filter(Boolean);
  } catch {
    return [];
  }
}

for (const pid of pids()) {
  try {
    execSync(isWin ? `taskkill /F /PID ${pid}` : `kill -9 ${pid}`, { stdio: "ignore" });
    console.log(`포트 ${port} 점유 프로세스 종료 (PID ${pid})`);
  } catch {
    /* 이미 종료됐거나 권한 없음 - 무시 */
  }
}
