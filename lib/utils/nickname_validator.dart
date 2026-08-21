/// 닉네임 규칙 — 2~10자, 한글·영문·숫자만.
///
/// 조건마다 다른 문구를 돌려줘야 사용자가 뭘 고쳐야 할지 안다.
/// "올바르지 않은 닉네임입니다" 한 줄로 뭉치지 않는다.
class NicknameValidator {
  const NicknameValidator._();

  static const int minLength = 2;
  static const int maxLength = 10;

  /// 완성형 한글 + 영문 + 숫자
  static final RegExp _allowed = RegExp(r'^[가-힣a-zA-Z0-9]+$');

  /// 자모만 있는 상태(ㄱ, ㅏ …). 한글 입력 조합 중에 잠깐 지나가는 단계다.
  static final RegExp _hasJamoOnly = RegExp(r'[ㄱ-ㅎㅏ-ㅣ]');

  /// 통과하면 null, 아니면 사용자에게 보여줄 문구.
  ///
  /// [whileTyping]이 true면 조합 중인 한글을 오류로 잡지 않는다.
  /// 'ㄱ'을 치자마자 "한글·영문·숫자만" 이라고 꾸짖으면 입력이 불쾌해진다.
  static String? validate(String raw, {bool whileTyping = false}) {
    final value = raw.trim();

    if (value.isEmpty) {
      return whileTyping ? null : '닉네임을 입력해 주세요';
    }
    if (raw.contains(' ')) {
      return '공백은 쓸 수 없어요';
    }
    if (value.runeLength < minLength) {
      return '$minLength자 이상 입력해 주세요';
    }
    if (value.runeLength > maxLength) {
      return '$maxLength자까지 쓸 수 있어요';
    }
    if (!_allowed.hasMatch(value)) {
      if (whileTyping && _hasJamoOnly.hasMatch(value)) return null;
      return '한글·영문·숫자만 쓸 수 있어요';
    }
    return null;
  }

  /// 서버에 물어봐도 되는 상태인지. 형식이 틀렸으면 중복확인을 부를 필요가 없다.
  static bool canCheckDuplicate(String raw) => validate(raw) == null;
}

extension on String {
  /// 한글 한 글자를 1자로 센다. Dart의 [length]는 UTF-16 코드 단위라
  /// 이모지 같은 서로게이트 쌍에서 2로 세지만, 우리 규칙은 이모지를 어차피 막는다.
  /// 그래도 길이 메시지가 엉뚱하게 나가지 않도록 룬 단위로 센다.
  int get runeLength => runes.length;
}
