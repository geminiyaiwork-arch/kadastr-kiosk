import 'package:intl/intl.dart';

final _grp = NumberFormat('#,###', 'ru'); // ru-RU → non-breaking-space grouping

/// Group a number like the web fmt() (ru-RU thin-space grouping).
String fmt(num n) => _grp.format(n);
