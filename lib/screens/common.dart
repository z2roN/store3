import 'dart:io';
import 'package:flutter/material.dart';
import '../api.dart';

bool get isMobile => Platform.isAndroid || Platform.isIOS;

void toast(BuildContext c, String m) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 2)));

Future<bool> confirm(BuildContext c, String msg) async =>
    await showDialog<bool>(
      context: c,
      builder: (_) => AlertDialog(content: Text(msg), actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('확인')),
      ]),
    ) ??
    false;

Future<void> guard(BuildContext c, Future<void> Function() f) async {
  try {
    await f();
  } on ApiError catch (e) {
    if (c.mounted) toast(c, e.message);
  } catch (e) {
    if (c.mounted) toast(c, '$e');
  }
}

Widget field(TextEditingController c, String label, {bool number = false, int lines = 1}) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        maxLines: lines,
        keyboardType: number ? TextInputType.number : null,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
      ),
    );
