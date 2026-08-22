/**
 * 지정한 포트를 점유 중인 프로세스를 종료한다. (Windows / macOS / Linux 공용)
 * 사용법: node scripts/free-port.js 5001
 */
const { execSync } = require("child_process");

const port = process.argv[2] || "5001";
const isWin = process.platform === "win32";

/**
 * netstat 한 줄에서 이 포트를 LISTEN 중인 PID를 뽑는다. 아니면 null.
 *
 *   "  TCP    0.0.0.0:5001    0.0.0.0:0    LISTENING    14344"
 *    → "14344"
 *
 * 정규식을 템플릿 리터럴에 넣지 않는다. `` `\\s` `` 는 템플릿 안에서 `\s`
 * **한 글자**로 축소돼 정규식이 "숫자 뒤의 문자 s"를 찾게 된다.
 * 그 탓에 이 스크립트는 한동안 아무 프로세스도 못 죽이고 있었다.
 * 그래서 정규식 대신 열 단위로 자른다.
 */
function pidFromNetstatLine(line) {
  const cols = line.trim().split(/\s+/);
  // TCP | 로컬주소 | 외부주소 | 상태 | PID  (UDP는 상태 열이 없다)
  if (cols.length < 5 || !/^TCP$/i.test(cols[0])) return null;

  const [, local, , state, pid] = cols;

  // 상태 문자열은 OS 로케일에 따라 번역될 수 있으므로 영문에만 기대지 않는다.
  // 대신 "외부 주소가 0.0.0.0:0 이면 LISTEN"이라는 성질을 함께 본다.
  const isListening = /^LISTEN/i.test(state) || cols[2] === "0.0.0.0:0";
  if (!isListening) return null;

  // IPv6는 [::]:5001, IPv4는 0.0.0.0:5001 — 마지막 콜론 뒤가 포트다.
  const localPort = local.slice(local.lastIndexOf(":") + 1);
  if (localPort !== port) return null;

  return pid && pid !== "0" ? pid : null;
}

function pids() {
  try {
    if (isWin) {
      const out = execSync("netstat -ano -p tcp", { encoding: "utf8" });
      const found = out
        .split(/\r?\n/)
        .map(pidFromNetstatLine)
        .filter(Boolean);
      return [...new Set(found)];
    }
    const out = execSync(`lsof -ti tcp:${port}`, { encoding: "utf8" });
    return out.split(/\s+/).filter(Boolean);
  } catch {
    // 점유 중인 프로세스가 없으면 netstat/lsof가 비정상 종료할 수 있다.
    return [];
  }
}

const targets = pids();
if (targets.length === 0) {
  console.log(`포트 ${port} 사용 중인 프로세스 없음`);
}
for (const pid of targets) {
  try {
    execSync(isWin ? `taskkill /F /PID ${pid}` : `kill -9 ${pid}`, {
      stdio: "ignore",
    });
    console.log(`포트 ${port} 점유 프로세스 종료 (PID ${pid})`);
  } catch {
    console.log(`PID ${pid} 를 종료하지 못했다 (이미 종료됐거나 권한 부족)`);
  }
}
