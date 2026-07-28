import 'dart:io';

void main(List<String> arguments) {
  final minimum = arguments.isEmpty ? 95.0 : double.parse(arguments.single);
  final file = File('coverage/lcov.info');
  if (!file.existsSync()) {
    stderr.writeln('coverage/lcov.info does not exist.');
    exitCode = 2;
    return;
  }

  var found = 0;
  var hit = 0;
  for (final line in file.readAsLinesSync()) {
    if (line.startsWith('LF:')) found += int.parse(line.substring(3));
    if (line.startsWith('LH:')) hit += int.parse(line.substring(3));
  }
  final percent = found == 0 ? 0.0 : hit * 100 / found;
  stdout.writeln(
    'Line coverage: $hit/$found (${percent.toStringAsFixed(2)}%)',
  );
  if (percent < minimum) {
    stderr.writeln('Required line coverage: ${minimum.toStringAsFixed(2)}%');
    exitCode = 1;
  }
}
