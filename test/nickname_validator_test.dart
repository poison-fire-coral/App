import 'package:flutter_test/flutter_test.dart';
import 'package:local_quest/utils/nickname_validator.dart';

void main() {
  String? v(String s) => NicknameValidator.validate(s);

  group('통과하는 것', () {
    for (final ok in ['모험가', 'ab', 'user1', '홍길동99', 'ABCdef1234', '가나다라마바사아자차']) {
      test('"$ok"', () => expect(v(ok), isNull));
    }
  });

  group('조건마다 다른 메시지를 준다', () {
    test('빈 값', () => expect(v(''), '닉네임을 입력해 주세요'));
    test('공백 하나뿐', () => expect(v('   '), '닉네임을 입력해 주세요'));
    test('2자 미만', () => expect(v('가'), '2자 이상 입력해 주세요'));
    test('10자 초과', () => expect(v('가나다라마바사아자차카'), '10자까지 쓸 수 있어요'));
    test('중간 공백', () => expect(v('hello world'), '공백은 쓸 수 없어요'));
    test('특수문자', () => expect(v('user@1'), '한글·영문·숫자만 쓸 수 있어요'));
    test('이모지', () => expect(v('모험가🔥'), '한글·영문·숫자만 쓸 수 있어요'));
  });

  group('한글 조합 중에는 꾸짖지 않는다', () {
    test('입력 중 자모는 통과', () {
      expect(NicknameValidator.validate('ㄱㄴ', whileTyping: true), isNull);
    });
    test('입력이 끝나면 자모는 막는다', () {
      expect(v('ㄱㄴ'), '한글·영문·숫자만 쓸 수 있어요');
    });
    test('입력 중 빈 값은 통과', () {
      expect(NicknameValidator.validate('', whileTyping: true), isNull);
    });
  });

  group('중복확인 버튼 활성 조건', () {
    test('형식이 맞아야 서버에 물어본다', () {
      expect(NicknameValidator.canCheckDuplicate('모험가'), isTrue);
      expect(NicknameValidator.canCheckDuplicate('가'), isFalse);
      expect(NicknameValidator.canCheckDuplicate('user@1'), isFalse);
    });
  });

  test('10자 경계 — 한글 10자는 통과, 11자는 막힌다', () {
    expect(v('가나다라마바사아자차'), isNull); // 10
    expect(v('가나다라마바사아자차카'), isNotNull); // 11
  });
}
