import 'package:intl/intl.dart';

final _dateTime = DateFormat('d MMM yyyy, HH:mm');
final _date = DateFormat('d MMM yyyy');

String fmtDateTime(DateTime d) => _dateTime.format(d);
String fmtDate(DateTime d) => _date.format(d);
String titleCase(String s) => s
    .toLowerCase()
    .split('_')
    .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
    .join(' ');
