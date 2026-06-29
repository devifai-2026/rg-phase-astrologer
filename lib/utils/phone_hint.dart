/// Reduce a hinted phone number to the bare 10-digit Indian local number.
///
/// Handles the shapes the Google Phone Number Hint returns, e.g.
/// "+919999911111", "919999911111", "09999911111", "9999911111" → "9999911111".
/// Returns null if it can't be reduced to exactly 10 digits.
String? normalizeTo10(String raw) {
  var d = raw.replaceAll(RegExp(r'\D'), ''); // keep digits only
  if (d.length > 10 && d.startsWith('91')) d = d.substring(d.length - 10);
  if (d.length == 11 && d.startsWith('0')) d = d.substring(1);
  if (d.length >= 10) d = d.substring(d.length - 10);
  return d.length == 10 ? d : null;
}
