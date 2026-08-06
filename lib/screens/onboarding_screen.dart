import 'package:flutter/material.dart';
import '../models/user_model.dart'; // UserModel 경로에 맞게 확인해 주세요.

// -----------------------------------------------------------------------------
// 온보딩 메인 화면 (PageView 기반 1d -> 1e -> 1f 스텝 이동)
// -----------------------------------------------------------------------------
class OnboardingScreen extends StatefulWidget {
  final UserModel? initialData;
  final ValueChanged<UserModel> onComplete;

  const OnboardingScreen({
    super.key,
    this.initialData,
    required this.onComplete,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0; // 0: 1d 프로필, 1: 1e 키워드, 2: 1f 위치 권한

  // 유저 입력 데이터 상태
  int _selectedAvatarIndex = 0;
  late TextEditingController _nicknameController;
  late TextEditingController _regionController;
  Set<String> _selectedKeywords = {'#골목산책', '#전통시장', '#바다·해안'};
  String _selectedIntensity = '보통';

  // 테마 색상 정의 (디자인 도큐먼트 스펙 기준)
  static const Color primaryRed = Color(0xFF9E2B1E);
  static const Color darkBorder = Color(0xFF2A1512);
  static const Color bgCream = Color(0xFFFFFDFB);
  static const Color subTextColor = Color(0x8C2A1512);

  final List<String> _keywordsList = [
    '#골목산책', '#로컬맛집', '#전통시장', '#카페투어',
    '#역사유적', '#바다·해안', '#산·트레킹', '#야경',
    '#사진스팟', '#공방·체험', '#축제', '#미술관', '#폐공간', '#주민이야기'
  ];

  @override
  void initState() {
    super.initState();
    // 기존에 넘겨받은 initialData가 있다면 기본값 설정
    _nicknameController = TextEditingController(text: widget.initialData?.nickname ?? '');
    _regionController = TextEditingController();

    if (widget.initialData != null && widget.initialData!.travelStyles.isNotEmpty) {
      _selectedKeywords = widget.initialData!.travelStyles.toSet();
    }
    if (widget.initialData != null && widget.initialData!.transport.isNotEmpty) {
      _selectedIntensity = widget.initialData!.transport;
    }
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _regionController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentStep < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      // 1f 위치 권한 단계까지 완료 시 UserModel 객체 생성 후 main.dart로 전달
      final newUser = UserModel(
        nickname: _nicknameController.text.trim().isEmpty ? '모험가' : _nicknameController.text.trim(),
        travelStyles: _selectedKeywords.toList(),
        transport: _selectedIntensity,
        level: widget.initialData?.level ?? 1, // 기존 레벨 유지 또는 1
        exp: widget.initialData?.exp ?? 0,     // 기존 경험치 유지 또는 0
      );

      widget.onComplete(newUser);
    }
  }

  void _previousPage() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgCream,
      body: SafeArea(
        child: Column(
          children: [
            // 상단 진행바 및 뒤로가기 헤더 (1f 단계에서는 숨김)
            if (_currentStep < 2) _buildHeader(),

            // 온보딩 컨텐츠 영역
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(), // 버튼 클릭으로만 이동
                onPageChanged: (index) {
                  setState(() => _currentStep = index);
                },
                children: [
                  _buildProfileStep(),  // 1d 프로필 설정
                  _buildKeywordStep(),  // 1e 키워드 선택
                  _buildPermissionStep(), // 1f 위치 권한 설정
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Header Widget (뒤로가기 + 프로그레스 바 + 스텝 표시)
  // ---------------------------------------------------------------------------
  Widget _buildHeader() {
    double progress = (_currentStep + 1) / 3.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: darkBorder, width: 1.5)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _previousPage,
            child: Text(
              _currentStep > 0 ? '← 뒤로' : '',
              style: const TextStyle(fontSize: 12, color: darkBorder, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: const Color(0xFFE8DCD6),
                borderRadius: BorderRadius.circular(3),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: progress,
                child: Container(
                  decoration: BoxDecoration(
                    color: primaryRed,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${_currentStep + 1} / 3',
            style: const TextStyle(fontSize: 12, color: darkBorder, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 1d. 온보딩 1 - 프로필 설정
  // ---------------------------------------------------------------------------
  Widget _buildProfileStep() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('모험가 이름을 정해주세요', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: darkBorder)),
          const SizedBox(height: 16),

          // 아바타 선택 영역
          Center(
            child: Column(
              children: [
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedAvatarIndex = (_selectedAvatarIndex + 1) % 6;
                    });
                  },
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: darkBorder, width: 1.5),
                      color: Colors.white,
                    ),
                    child: Center(
                      child: Text(
                        '아바타\n${_selectedAvatarIndex + 1}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 10, color: subTextColor, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                const Text('탭하여 아바타 변경 (기본 6종)', style: TextStyle(fontSize: 10, color: subTextColor)),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 닉네임 입력 박스
          _buildCustomTextBox(
            child: TextField(
              controller: _nicknameController,
              style: const TextStyle(fontSize: 13, color: darkBorder),
              decoration: const InputDecoration(
                hintText: '닉네임 입력 (2~10자)',
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Expanded(
                child: Text('사용 가능한 이름입니다', style: TextStyle(fontSize: 11, color: subTextColor)),
              ),
              _buildChip('중복확인', isSelected: false, onTap: () {}),
            ],
          ),
          const SizedBox(height: 16),

          // 아바타 설명 박스
          _buildDashedBox('아바타 = 기본 프리셋 6종 중 선택 (사진 업로드는 추후 지원)'),
          const SizedBox(height: 12),

          // 홈 지역 입력 박스
          _buildCustomTextBox(
            child: TextField(
              controller: _regionController,
              style: const TextStyle(fontSize: 13, color: darkBorder),
              decoration: const InputDecoration(
                hintText: '홈 지역 (선택 · 미입력 시 현재 위치)',
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),

          const Spacer(),
          _buildPrimaryButton('다음', onTap: _nextPage),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 1e. 온보딩 2 - 키워드 & 활동 강도 선택
  // ---------------------------------------------------------------------------
  Widget _buildKeywordStep() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('관심 키워드를 골라주세요', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: darkBorder)),
          const SizedBox(height: 4),
          const Text('복수 선택 · 3개 이상 (추후 퀘스트 추천에 사용)', style: TextStyle(fontSize: 11, color: subTextColor)),
          const SizedBox(height: 16),

          // 키워드 칩 그리드
          Wrap(
            spacing: 6,
            runSpacing: 8,
            children: _keywordsList.map((keyword) {
              final isSelected = _selectedKeywords.contains(keyword);
              return _buildChip(
                keyword,
                isSelected: isSelected,
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      _selectedKeywords.remove(keyword);
                    } else {
                      _selectedKeywords.add(keyword);
                    }
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          // 활동 강도 설정 박스
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: darkBorder, width: 1.5),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('활동 강도', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: darkBorder)),
                const SizedBox(height: 8),
                Row(
                  children: ['가볍게', '보통', '많이 걷기'].map((intensity) {
                    final isSelected = _selectedIntensity == intensity;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _buildChip(
                        intensity,
                        isSelected: isSelected,
                        onTap: () {
                          setState(() => _selectedIntensity = intensity);
                        },
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),

          const Spacer(),
          const Center(child: Text('3 / 3 위치 권한 설정 →', style: TextStyle(fontSize: 11, color: subTextColor))),
          const SizedBox(height: 6),
          _buildPrimaryButton('다음', onTap: _nextPage),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 1f. 위치 권한 안내 (필수 게이트)
  // ---------------------------------------------------------------------------
  Widget _buildPermissionStep() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Spacer(),
          // 위치 일러스트 Placeholder
          _buildDashedBox(
            '위치 일러스트\nplaceholder',
            height: 120,
            alignment: Alignment.center,
          ),
          const SizedBox(height: 20),

          const Text('위치 권한이 반드시 필요해요', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: darkBorder)),
          const SizedBox(height: 10),
          const Text(
            '퀘스트 탐색과 도달 인증이 GPS로만 가능합니다.\n허용하지 않으면 서비스를 이용할 수 없습니다.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: subTextColor, height: 1.4),
          ),
          const SizedBox(height: 24),

          _buildPrimaryButton('권한 허용하기', onTap: _nextPage),
          const SizedBox(height: 8),

          // 나중에 버튼 (점선 외곽선)
          GestureDetector(
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('위치 권한에 동의해야 모험을 시작할 수 있습니다.')),
              );
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFB6A49E), width: 1.5, style: BorderStyle.solid),
                borderRadius: BorderRadius.circular(18),
                color: const Color(0xFFF6EFEC),
              ),
              child: const Center(
                child: Text('나중에 (진행 불가)', style: TextStyle(fontSize: 14, color: Color(0xFFA2908A))),
              ),
            ),
          ),
          const SizedBox(height: 16),

          _buildDashedBox('거부 시 : 안내 모달 → 이 화면 유지 · 앱 설정 바로가기 제공', fontSize: 11),
          const Spacer(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 공통 UI 컴포넌트 헬퍼 (디자인 스펙 규격 준수)
  // ---------------------------------------------------------------------------
  Widget _buildCustomTextBox({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: darkBorder, width: 1.5),
        borderRadius: BorderRadius.circular(7),
      ),
      child: child,
    );
  }

  Widget _buildDashedBox(String text, {double? height, Alignment alignment = Alignment.centerLeft, double fontSize = 12}) {
    return Container(
      height: height,
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      alignment: alignment,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFA2908A), width: 1.5),
        borderRadius: BorderRadius.circular(7),
        color: const Color(0xFFFFFDFB),
      ),
      child: Text(
        text,
        textAlign: alignment == Alignment.center ? TextAlign.center : TextAlign.left,
        style: TextStyle(fontSize: fontSize, color: const Color(0xFF6D5A55), height: 1.3),
      ),
    );
  }

  Widget _buildChip(String label, {required bool isSelected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? primaryRed : bgCream,
          border: Border.all(color: isSelected ? primaryRed : darkBorder, width: 1.2),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.white : darkBorder,
          ),
        ),
      ),
    );
  }

  Widget _buildPrimaryButton(String label, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: primaryRed,
          border: Border.all(color: darkBorder, width: 1.5),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
      ),
    );
  }
}