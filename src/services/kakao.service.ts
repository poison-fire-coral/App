import axios from 'axios';

export interface KakaoPlace {
  id: string;
  place_name: string;
  category_name: string;
  category_group_code: string;
  phone: string;
  address_name: string;
  road_address_name: string;
  x: string; // 경도 (lng)
  y: string; // 위도 (lat)
  place_url: string;
  distance: string;
}

export class KakaoService {
  private static readonly KAKAO_API_URL = 'https://dapi.kakao.com/v2/local/search/keyword.json';

  /// 지정한 키워드(공원, 시장, 카페 등)로 주변 장소 검색
  static async searchNearbyPlaces(
    lat: number,
    lng: number,
    keyword: string,
    radiusM: number = 3000
  ): Promise<KakaoPlace[]> {
    try {
      const response = await axios.get(this.KAKAO_API_URL, {
        headers: {
          Authorization: `KakaoAK ${process.env.KAKAO_REST_API_KEY}`,
        },
        params: {
          query: keyword,
          x: lng.toString(),
          y: lat.toString(),
          radius: radiusM,
          sort: 'distance',
        },
      });

      return response.data.documents || [];
    } catch (error) {
      console.error('카카오 로컬 API 호출 실패:', error);
      return [];
    }
  }
}