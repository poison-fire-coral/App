import { Router, Request, Response } from "express";

const router = Router();

/**
 * GET /privacy
 * Google Play Console 및 서비스용 공개 개인정보 처리방침 웹페이지
 */
router.get("/privacy", (_req: Request, res: Response) => {
  const htmlContent = `
<!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>개인정보 처리방침 - 로컬퀘스트 (Local Quest)</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
            line-height: 1.7;
            color: #333;
            max-width: 800px;
            margin: 0 auto;
            padding: 24px;
        }
        h1 { border-bottom: 2px solid #2563eb; padding-bottom: 12px; color: #1e40af; font-size: 24px; }
        h2 { margin-top: 32px; color: #1d4ed8; font-size: 18px; }
        ul { padding-left: 20px; }
        li { margin-bottom: 8px; font-size: 15px; }
        p { font-size: 15px; margin-bottom: 12px; }
        .footer { margin-top: 48px; padding-top: 20px; border-top: 1px solid #e5e7eb; font-size: 13px; color: #6b7280; }
    </style>
</head>
<body>
    <h1>개인정보 처리방침</h1>
    <p>본 개인정보 처리방침은 '로컬퀘스트(Local Quest)'(이하 "서비스")가 이용자의 개인정보를 어떻게 수집, 이용, 보관 및 보호하는지 설명합니다.</p>

    <h2>1. 수집하는 개인정보 항목</h2>
    <ul>
        <li><strong>필수 항목:</strong> 소셜 Provider(카카오/구글), Provider UID, 이메일, 닉네임, 서비스 이용 기록, 접속 로그, 기기 정보</li>
        <li><strong>선택 항목:</strong> 프로필 아바타 ID, 선호 키워드, 활동 지역, 퀘스트 인증 사진</li>
    </ul>

    <h2>2. 개인정보의 수집 및 이용목적</h2>
    <ul>
        <li><strong>회원 관리:</strong> 소셜 로그인을 통한 본인 식별, 불량 회원의 부정 이용(GPS 모의 위치 등) 방지</li>
        <li><strong>서비스 제공:</strong> 위치 기반 퀘스트 추천, 방문 인증, 레벨 및 경험치(EXP) 산정</li>
    </ul>

    <h2>3. 위치정보의 이용 및 보유</h2>
    <ul>
        <li>회사는 위치정보를 활용하여 이용자 주변의 퀘스트 스팟 제공, 위치 도착 인증, 이동 거리 계산 서비스를 제공합니다.</li>
        <li>회사는 퀘스트 방문 인증 시점에 한하여 위치 좌표를 이용하며, 법령에 따른 기록 외에 위치 좌표 자체를 영구 저장하지 않습니다.</li>
    </ul>

    <h2>4. 개인정보의 보유 및 파기</h2>
    <p>원칙적으로 회원 탈퇴 시 이용자의 개인정보는 지체 없이 파기됩니다. 단, 부정 이용 방지 및 법령에 따라 보존할 필요가 있는 경우 관련 법령이 정한 기간 동안 보관합니다.</p>

    <h2>5. 개인정보 보호책임자 및 문의처</h2>
    <p>서비스 이용 중 발생한 개인정보 보호 관련 문의사항은 아래 연락처로 문의해 주시기 바랍니다.</p>
    <ul>
        <li><strong>서비스명:</strong> 로컬퀘스트 (Local Quest)</li>
        <li><strong>문의 이메일:</strong> support@localquest.com</li>
    </ul>

    <div class="footer">
        <p>시행 일자: 2026년 1월 1일</p>
    </div>
</body>
</html>
  `;

  res.setHeader("Content-Type", "text/html; charset=utf-8");
  res.status(200).send(htmlContent);
});

export default router;