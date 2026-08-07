const express = require('express');
const axios = require('axios');
const dotenv = require('dotenv');
const cors = require('cors');

dotenv.config();

const app = express();
app.use(cors());
app.use(express.json());

const KAKAO_API_URL = 'https://dapi.kakao.com/v2/local';

// 💡 [프론트엔드 역할] 백엔드가 잘 작동하는지 테스트할 수 있는 간단한 HTML 화면
app.get('/', (req, res) => {
  res.send(`
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>카카오 API 백엔드 테스트</title>
      <style>
        body { font-family: sans-serif; padding: 20px; max-width: 600px; margin: 0 auto; }
        input { padding: 8px; width: 70%; font-size: 16px; }
        button { padding: 8px 15px; font-size: 16px; cursor: pointer; }
        pre { background: #f4f4f4; padding: 15px; border-radius: 5px; overflow-x: auto; }
      </style>
    </head>
    <body>
      <h2>🔍 카카오 장소 검색 백엔드 테스트</h2>
      <input type="text" id="searchInput" value="판교역" placeholder="검색어 입력">
      <button onclick="searchPlace()">검색</button>
      <h3>응답 결과 (JSON):</h3>
      <pre id="result">검색 버튼을 눌러보세요.</pre>

      <script>
        async function searchPlace() {
          const query = document.getElementById('searchInput').value;
          const resultEl = document.getElementById('result');
          resultEl.innerText = '로딩 중...';

          try {
            const res = await fetch(\`/api/map/search?query=\${encodeURIComponent(query)}\`);
            const data = await res.json();
            resultEl.innerText = JSON.stringify(data, null, 2);
          } catch (err) {
            resultEl.innerText = '에러 발생: ' + err.message;
          }
        }
      </script>
    </body>
    </html>
  `);
});

// 키워드로 장소 검색 API
app.get('/api/map/search', async (req, res) => {
  const { query } = req.query;

  if (!query) {
    return res.status(400).json({ error: '검색어가 필요합니다.' });
  }

  try {
    const response = await axios.get(`${KAKAO_API_URL}/search/keyword.json`, {
      headers: {
        Authorization: `KakaoAK ${process.env.KAKAO_REST_API_KEY?.trim()}`,
      },
      params: { query },
    });
    res.json(response.data);
  } catch (error) {
    console.error('카카오 API 에러:', error.response?.data || error.message);
    res.status(500).json({ error: '카카오 API 호출 실패', details: error.message });
  }
});

const PORT = process.env.PORT || 5000;
app.listen(PORT, () => {
  console.log(`Server is running on http://localhost:${PORT}`);
});