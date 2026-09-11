import { Router, Request, Response } from "express";

/**
 * 공개 약관 4종 (서비스, 위치기반서비스, 개인정보, 마케팅) 및 계정 삭제 안내
 */
const SERVICE_NAME = "로컬 퀘스트 (Local Quest)";
const CONTACT_EMAIL = "raenpyu73@gmail.com"; // TODO(운영): 실제 문의 주소로 교체
const EFFECTIVE_DATE = "2026년 9월 12일";          // 서비스 시행일
const PROVIDER_NAME = "로컬 퀘스트 운영팀";          // 상호명 또는 이름

const STYLE = `
  :root { color-scheme: light dark; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Malgun Gothic", sans-serif;
    line-height: 1.75; color: #2B2520; background: #FBF6F3;
    max-width: 760px; margin: 0 auto; padding: 28px 20px 72px;
    -webkit-text-size-adjust: 100%;
  }
  h1 { font-size: 22px; margin: 0 0 6px; }
  .meta { color: #7A6E64; font-size: 13px; margin: 0 0 28px; }
  h2 { font-size: 17px; margin: 32px 0 8px; color: #9E2B1E; }
  p, li { font-size: 15px; }
  ul { padding-left: 20px; }
  li { margin-bottom: 6px; }
  table { border-collapse: collapse; width: 100%; font-size: 14px; margin: 8px 0; }
  th, td { border: 1px solid #DED4C2; padding: 8px 10px; text-align: left; vertical-align: top; }
  th { background: #F3EAE3; font-weight: 600; }
  .foot { margin-top: 48px; padding-top: 16px; border-top: 1px solid #DED4C2;
          font-size: 13px; color: #7A6E64; }
  @media (prefers-color-scheme: dark) {
    body { color: #EDE5D7; background: #191512; }
    h2 { color: #D8705F; }
    th { background: #2A231D; }
    th, td { border-color: #3A322A; }
    .meta, .foot { color: #9A8E82; }
  }
`;

function page(title: string, body: string): string {
  return `<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>${title} · ${SERVICE_NAME}</title>
<style>${STYLE}</style>
</head>
<body>
<h1>${title}</h1>
<p class="meta">${SERVICE_NAME} · 시행일 ${EFFECTIVE_DATE}</p>
${body}
<div class="foot">
  <p>문의: <a href="mailto:${CONTACT_EMAIL}">${CONTACT_EMAIL}</a></p>
  <p>${PROVIDER_NAME}</p>
</div>
</body>
</html>`;
}

const router = Router();

function send(res: Response, title: string, body: string) {
  res.setHeader("Content-Type", "text/html; charset=utf-8");
  res.setHeader("Cache-Control", "public, max-age=3600");
  res.status(200).send(page(title, body));
}

// ---------------------------------------------------------------------------
// 1. 서비스 이용약관
// ---------------------------------------------------------------------------
router.get("/terms/service", (_req: Request, res: Response) => {
  send(
    res,
    "서비스 이용약관",
    `
<h2>제1조 (목적)</h2>
<p>이 약관은 ${PROVIDER_NAME}(이하 "회사")이 제공하는 ${SERVICE_NAME}(이하 "서비스")의
이용 조건과 절차, 회사와 이용자의 권리·의무를 정하는 것을 목적으로 합니다.</p>

<h2>제2조 (서비스의 내용)</h2>
<ul>
  <li>회사는 이용자의 위치를 기준으로 주변의 장소 기반 퀘스트를 제공합니다.</li>
  <li>이용자가 해당 장소에 도달해 인증하면 경험치(EXP)·레벨·배지가 지급됩니다.</li>
  <li>퀘스트의 종류·보상·난이도는 서비스 운영상 필요에 따라 변경될 수 있습니다.</li>
</ul>

<h2>제3조 (회원가입)</h2>
<ul>
  <li>회원가입은 카카오 또는 구글 계정을 통한 소셜 로그인으로 이루어집니다.</li>
  <li>가입 시 필수 약관(서비스 이용약관, 위치기반서비스 이용약관)에 동의해야 합니다.</li>
  <li>마케팅 정보 수신은 선택 사항이며, 동의하지 않아도 서비스를 이용할 수 있습니다.</li>
</ul>

<h2>제4조 (부정 이용 금지)</h2>
<p>다음 행위는 금지되며, 적발 시 해당 인증의 보상이 지급되지 않고 기록이 남습니다.
반복될 경우 서비스 이용이 제한될 수 있습니다.</p>
<ul>
  <li>위치 조작 애플리케이션(모의 위치) 등을 이용해 실제로 방문하지 않은 장소를 인증하는 행위</li>
  <li>타인이 촬영한 사진이나 과거에 촬영한 사진을 인증에 사용하는 행위</li>
  <li>이동 수단을 이용해 도보 이동으로 볼 수 없는 속도로 연속 인증하는 행위</li>
  <li>자동화된 수단으로 서비스에 접근하거나 반복 요청을 보내는 행위</li>
</ul>

<h2>제5조 (게시물과 사진)</h2>
<ul>
  <li>이용자가 인증 과정에서 등록한 사진과 기록의 저작권은 이용자에게 있습니다.</li>
  <li>이용자가 공개로 설정한 사진은 서비스 내에서 다른 이용자에게 노출될 수 있습니다.
      공개 여부는 인증할 때마다 선택할 수 있고, 기본값은 설정에서 바꿀 수 있습니다.</li>
  <li>타인의 초상권·저작권을 침해하는 사진을 등록해서는 안 됩니다.</li>
</ul>

<h2>제6조 (안전에 관한 고지)</h2>
<p>서비스는 이용자를 실제 장소로 이동하게 합니다. 이용자는 이동 중 교통 법규와
현장의 안전 수칙을 준수해야 하며, 다음을 지켜 주시기 바랍니다.</p>
<ul>
  <li>보행·운전 중 화면을 보지 마십시오.</li>
  <li>출입이 금지된 장소, 사유지, 위험 지역에 진입하지 마십시오.</li>
  <li>기상·시간대 등 현장 여건상 위험하다고 판단되면 퀘스트를 중단하십시오.</li>
</ul>

<h2>제7조 (회원 탈퇴)</h2>
<p>이용자는 앱의 설정 화면에서 언제든지 탈퇴할 수 있습니다. 탈퇴 시 계정과
관련 기록(레벨, 경험치, 퀘스트 완료 이력, 배지)은 즉시 삭제되며 복구할 수 없습니다.</p>

<h2>제8조 (책임의 한계)</h2>
<ul>
  <li>회사는 천재지변, 통신 장애 등 회사의 통제를 벗어난 사유로 인한 서비스 중단에 책임을 지지 않습니다.</li>
  <li>퀘스트 장소의 정보는 공공 데이터(한국관광공사 등)와 지도 서비스에 기반하며,
      현장의 실제 상황(폐업, 출입 제한 등)과 다를 수 있습니다.</li>
</ul>

<h2>제9조 (약관의 변경)</h2>
<p>회사는 약관을 변경할 수 있으며, 변경 시 서비스 내 공지 또는 이 페이지를 통해
시행일 7일 전(이용자에게 불리한 변경은 30일 전)까지 알립니다.</p>
`
  );
});

// ---------------------------------------------------------------------------
// 2. 위치기반서비스 이용약관
// ---------------------------------------------------------------------------
router.get("/terms/location", (_req: Request, res: Response) => {
  send(
    res,
    "위치기반서비스 이용약관",
    `
<h2>제1조 (목적)</h2>
<p>이 약관은 회사가 제공하는 위치기반서비스에 대해 회사와 개인위치정보주체 간의
권리·의무 및 책임사항을 규정함을 목적으로 합니다.
「위치정보의 보호 및 이용 등에 관한 법률」에 따릅니다.</p>

<h2>제2조 (위치정보의 이용 목적)</h2>
<ul>
  <li><strong>주변 퀘스트 탐색</strong> — 현재 위치를 기준으로 가까운 퀘스트를 찾아 보여줍니다.</li>
  <li><strong>지도 표시</strong> — 지도에서 보고 있는 영역의 퀘스트를 조회합니다.</li>
  <li><strong>도달 인증</strong> — 퀘스트 지점의 인증 반경 안에 있는지 확인합니다.</li>
  <li><strong>거리 계산과 보상 산정</strong> — 남은 거리 표시, 처음 방문한 지역 판정.</li>
  <li><strong>부정 이용 방지</strong> — 모의 위치 사용 여부와 비정상적인 이동 속도 확인.</li>
</ul>

<h2>제3조 (위치정보의 수집 시점)</h2>
<p>회사는 <strong>앱이 화면에 떠 있는 동안에만</strong> 위치를 수집합니다.
백그라운드 위치 권한(ACCESS_BACKGROUND_LOCATION)은 요청하지 않으며,
앱을 내리면 위치 수집이 중단됩니다.</p>
<p>수집이 일어나는 구체적인 시점은 다음과 같습니다.</p>
<ul>
  <li>홈 화면을 열거나 새로고침할 때</li>
  <li>지도를 열고 움직일 때</li>
  <li>퀘스트를 진행하며 목표 지점까지의 거리를 확인할 때</li>
  <li>도달 인증 버튼을 누를 때</li>
</ul>

<h2>제4조 (위치정보의 보유와 파기)</h2>
<table>
  <tr><th>구분</th><th>보유 여부</th><th>기간</th></tr>
  <tr>
    <td>탐색·지도·거리 계산에 쓰인 좌표</td>
    <td>저장하지 않음 (요청 처리 후 폐기)</td>
    <td>—</td>
  </tr>
  <tr>
    <td>도달 인증 시점의 좌표와 정확도</td>
    <td>저장함 (인증 기록의 근거)</td>
    <td>회원 탈퇴 시까지</td>
  </tr>
  <tr>
    <td>위치정보 이용·제공 사실 확인자료</td>
    <td>저장함 (법정 의무)</td>
    <td>6개월</td>
  </tr>
</table>
<p>회사는 이동 경로를 지속적으로 추적하거나 저장하지 않습니다.</p>

<h2>제5조 (제3자 제공)</h2>
<p>회사는 개인위치정보를 제3자에게 제공하지 않습니다. 다만 서비스 제공에
필요한 범위에서 다음 사업자의 API를 호출하며, 이때 좌표가 전달됩니다.</p>
<ul>
  <li>카카오(지도 표시 및 장소 검색)</li>
  <li>한국관광공사(주변 관광 정보 조회)</li>
</ul>

<h2>제6조 (개인위치정보주체의 권리)</h2>
<ul>
  <li>위치정보 수집에 대한 동의를 언제든지 철회할 수 있습니다. 기기의 설정에서
      앱의 위치 권한을 해제하면 됩니다. 이 경우 퀘스트 탐색과 인증은 이용할 수 없습니다.</li>
  <li>위치정보 이용·제공 사실 확인자료의 열람·고지를 요구할 수 있습니다.</li>
  <li>위 권리 행사는 ${CONTACT_EMAIL} 로 요청할 수 있습니다.</li>
</ul>

<h2>제7조 (8세 이하 아동 등의 보호)</h2>
<p>회사는 8세 이하의 아동, 피성년후견인, 장애인복지법상 정신적 장애를 가진 사람으로서
장애인고용촉진 및 직업재활법상 중증장애인에 해당하는 사람의 보호의무자가 동의하는
경우 개인위치정보주체 본인의 동의가 있는 것으로 봅니다.</p>

<h2>제8조 (위치정보관리책임자)</h2>
<p>${PROVIDER_NAME} · ${CONTACT_EMAIL}</p>
`
  );
});

// ---------------------------------------------------------------------------
// 3. 개인정보 처리방침
// ---------------------------------------------------------------------------
router.get("/privacy", (_req: Request, res: Response) => {
  send(
    res,
    "개인정보 처리방침",
    `
<p>${SERVICE_NAME}(이하 "서비스")는 이용자의 개인정보를 소중히 다루며,
「개인정보 보호법」 등 관련 법령을 준수합니다.</p>

<h2>1. 수집하는 개인정보 항목</h2>
<table>
  <tr><th>구분</th><th>항목</th><th>수집 시점</th></tr>
  <tr>
    <td>필수</td>
    <td>소셜 제공자(카카오/구글), 제공자 회원번호, 이메일, 닉네임</td>
    <td>회원가입</td>
  </tr>
  <tr>
    <td>필수</td>
    <td>위치정보(위도·경도·정확도)</td>
    <td>퀘스트 탐색 및 도달 인증</td>
  </tr>
  <tr>
    <td>선택</td>
    <td>아바타, 관심 키워드, 활동 지역, 활동 강도</td>
    <td>온보딩</td>
  </tr>
  <tr>
    <td>선택</td>
    <td>퀘스트 인증 사진, 한 줄 기록</td>
    <td>퀘스트 인증</td>
  </tr>
  <tr>
    <td>선택</td>
    <td>푸시 알림 토큰(FCM), 기기 플랫폼</td>
    <td>알림을 켤 때</td>
  </tr>
  <tr>
    <td>자동</td>
    <td>서비스 이용 기록, 접속 로그, 모의 위치 사용 여부</td>
    <td>서비스 이용 중</td>
  </tr>
</table>

<h2>2. 이용 목적</h2>
<ul>
  <li><strong>회원 식별과 관리</strong> — 소셜 로그인을 통한 본인 확인, 중복 가입 방지</li>
  <li><strong>서비스 제공</strong> — 위치 기반 퀘스트 추천, 도달 인증, 경험치·레벨·배지 산정</li>
  <li><strong>알림 발송</strong> — 주변 퀘스트 알림(켠 경우에 한함)</li>
  <li><strong>부정 이용 방지</strong> — 모의 위치 및 비정상 이동 속도 탐지, 기록 보관</li>
</ul>

<h2>3. 보유 및 파기</h2>
<ul>
  <li>회원 탈퇴 시 개인정보는 <strong>지체 없이 파기</strong>됩니다. 계정과 함께
      퀘스트 완료 기록, 배지, 인증 사진, 알림 토큰이 삭제됩니다.</li>
  <li>다만 다음은 법령에 따라 별도 보관합니다.
    <ul>
      <li>위치정보 이용·제공 사실 확인자료: 6개월 (위치정보법 제16조)</li>
      <li>표시·광고에 관한 기록: 6개월 (전자상거래법)</li>
    </ul>
  </li>
</ul>

<h2>4. 제3자 제공 및 처리 위탁</h2>
<p>회사는 개인정보를 제3자에게 제공하지 않습니다. 서비스 제공에 필요한 범위에서
아래 업무를 위탁합니다.</p>
<table>
  <tr><th>수탁자</th><th>위탁 업무</th></tr>
  <tr><td>Amazon Web Services</td><td>인증 사진 저장</td></tr>
  <tr><td>Google (Firebase Cloud Messaging)</td><td>푸시 알림 발송</td></tr>
  <tr><td>카카오</td><td>지도 표시 및 장소 검색</td></tr>
</table>

<h2>5. 이용자의 권리</h2>
<ul>
  <li>개인정보의 열람·정정·삭제·처리정지를 요구할 수 있습니다.</li>
  <li>프로필과 관심 키워드는 앱의 설정 화면에서 직접 수정할 수 있습니다.</li>
  <li>회원 탈퇴는 앱의 <strong>설정 → 회원 탈퇴</strong>에서 언제든지 가능합니다.</li>
  <li>그 밖의 요청은 ${CONTACT_EMAIL} 로 접수하며, 접수일로부터 10일 이내에 조치합니다.</li>
</ul>

<h2>6. 개인정보의 안전성 확보</h2>
<ul>
  <li>모든 통신은 HTTPS로 암호화합니다.</li>
  <li>인증 토큰은 기기의 보안 저장소(Android Keystore)에 보관합니다.</li>
  <li>인증 사진은 업로드 시 크기를 줄이며, 이 과정에서 촬영 위치가 담긴
      EXIF 정보가 제거됩니다.</li>
</ul>

<h2>7. 개인정보 보호책임자</h2>
<p>${PROVIDER_NAME} · ${CONTACT_EMAIL}</p>

<h2>8. 처리방침의 변경</h2>
<p>이 방침이 변경되는 경우 시행일 7일 전부터 이 페이지를 통해 알립니다.</p>
`
  );
});

// ---------------------------------------------------------------------------
// 4. 마케팅 정보 수신 동의
// ---------------------------------------------------------------------------
router.get("/terms/marketing", (_req: Request, res: Response) => {
  send(
    res,
    "마케팅 정보 수신 동의",
    `
<h2>제1조 (목적)</h2>
<p>${SERVICE_NAME}가 제공하는 이벤트, 혜택, 신규 퀘스트 및 맞춤형 정보 안내를 위해 마케팅 정보를 발송합니다.</p>

<h2>제2조 (수집 및 이용 항목)</h2>
<ul>
  <li>이메일 주소, 푸시 알림 토큰(FCM), 서비스 이용 기록</li>
</ul>

<h2>제3조 (보유 및 이용 기간)</h2>
<p><strong>회원 탈퇴 시 또는 마케팅 동의 철회 시까지</strong> 보관 및 이용됩니다.</p>

<h2>제4조 (동의 거부권)</h2>
<p>마케팅 정보 수신 동의는 선택 사항이며, 동의하지 않아도 서비스의 기본 기능(퀘스트 수행 및 인증)을 동일하게 이용하실 수 있습니다.</p>
`
  );
});

// ---------------------------------------------------------------------------
// 5. 계정 삭제 안내 (웹)
// ---------------------------------------------------------------------------
router.get("/account/delete", (_req: Request, res: Response) => {
  send(
    res,
    "계정 삭제 안내",
    `
<h2>앱에서 바로 삭제하기</h2>
<p>가장 빠른 방법입니다. 앱을 실행한 뒤:</p>
<ul>
  <li><strong>홈 우측 상단 설정(⚙︎) → 맨 아래 &lsquo;회원 탈퇴&rsquo;</strong></li>
  <li>확인 창에서 &lsquo;탈퇴하기&rsquo;를 누르면 즉시 처리됩니다.</li>
</ul>

<h2>앱을 이미 지웠다면</h2>
<p>아래 주소로 <strong>가입에 사용한 소셜 계정의 이메일</strong>과 함께
&ldquo;계정 삭제 요청&rdquo;이라고 보내 주세요. 본인 확인 후 처리합니다.</p>
<p><a href="mailto:${CONTACT_EMAIL}?subject=계정%20삭제%20요청">${CONTACT_EMAIL}</a></p>

<h2>삭제되는 것</h2>
<ul>
  <li>계정 정보(소셜 제공자 회원번호, 이메일, 닉네임, 아바타)</li>
  <li>레벨, 경험치, 연속 접속 기록</li>
  <li>퀘스트 완료 이력과 획득한 배지</li>
  <li>인증 사진과 한 줄 기록</li>
  <li>푸시 알림 토큰</li>
</ul>
<p>삭제는 <strong>즉시, 되돌릴 수 없이</strong> 이루어집니다. 유예 기간이 없습니다.</p>

<h2>삭제 후에도 남는 것</h2>
<p>법령이 보관을 요구하는 다음 자료는 정해진 기간 동안 계정과 분리해 보관합니다.</p>
<ul>
  <li>위치정보 이용·제공 사실 확인자료: 6개월 (위치정보법 제16조)</li>
</ul>
`
  );
});

export default router;