class Validators {
  static bool isEmail(String value) {
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    return emailRegex.hasMatch(value);
  }

  static bool isPasswordStrong(String value) {
    return value.length >= 6;
  }

  static bool isFullNameValid(String value) {
    final trimmed = value.trim();
    return trimmed.split(' ').length >= 2 && trimmed.length > 3;
  }
}
