import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'api.dart';

/// 영수증(80mm 롤 용지) PDF 생성 및 인쇄
Future<pw.Document> buildReceipt(Map sale, List items, Map settings) async {
  final reg = pw.Font.ttf(await rootBundle.load('assets/fonts/NanumGothic-Regular.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/NanumGothic-Bold.ttf'));
  final doc = pw.Document(theme: pw.ThemeData.withFont(base: reg, bold: bold));
  pw.Widget line(String a, String b, {bool strong = false}) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [pw.Text(a, style: pw.TextStyle(fontSize: 9, fontWeight: strong ? pw.FontWeight.bold : null)), pw.Text(b, style: pw.TextStyle(fontSize: 9, fontWeight: strong ? pw.FontWeight.bold : null))],
      );
  final dt = DateTime.tryParse('${sale['SaleDate']}') ?? DateTime.now();
  doc.addPage(pw.Page(
    pageFormat: const PdfPageFormat(80 * PdfPageFormat.mm, double.infinity, marginAll: 4 * PdfPageFormat.mm),
    build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.Center(child: pw.Text(settings['storeName'] ?? '매장', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold))),
      if ((settings['bizNo'] ?? '').isNotEmpty) pw.Center(child: pw.Text('사업자번호 ${settings['bizNo']}', style: const pw.TextStyle(fontSize: 8))),
      if ((settings['address'] ?? '').isNotEmpty) pw.Center(child: pw.Text(settings['address'], style: const pw.TextStyle(fontSize: 8))),
      if ((settings['phone'] ?? '').isNotEmpty) pw.Center(child: pw.Text('TEL ${settings['phone']}', style: const pw.TextStyle(fontSize: 8))),
      pw.SizedBox(height: 6),
      line('영수증 ${sale['SaleNo']}', ''),
      line(DateFormat('yyyy-MM-dd HH:mm').format(dt), '${sale['UserName'] ?? ''}'),
      if (sale['CustomerName'] != null) line('고객', '${sale['CustomerName']}'),
      pw.Divider(),
      for (final i in items) ...[
        pw.Text('${i['Name']}${asInt(i['UnitQty']) > 1 ? ' [${i['UnitName']} ×${i['UnitQty']}]' : ''}', style: const pw.TextStyle(fontSize: 9)),
        line('  ${won(asInt(i['Price']))} x ${i['Qty']}', won(asInt(i['Amount']))),
      ],
      pw.Divider(),
      if (asInt(sale['Discount']) > 0) line('할인', '-${won(asInt(sale['Discount']))}'),
      line('합계', won(asInt(sale['Total'])), strong: true),
      line('결제(${sale['PayMethod']})', won(asInt(sale['Paid']))),
      if (asInt(sale['Total']) - asInt(sale['Paid']) > 0) line('외상', won(asInt(sale['Total']) - asInt(sale['Paid']))),
      if (sale['Cancelled'] == true) pw.Center(child: pw.Text('*** 취소된 판매 ***', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
      pw.SizedBox(height: 8),
      pw.Center(child: pw.Text(settings['receiptFooter'] ?? '이용해 주셔서 감사합니다', style: const pw.TextStyle(fontSize: 9))),
    ]),
  ));
  return doc;
}

Future<void> printReceipt(Map sale, List items, Map settings) async {
  final doc = await buildReceipt(sale, items, settings);
  await Printing.layoutPdf(
    name: '영수증_${sale['SaleNo']}',
    format: const PdfPageFormat(80 * PdfPageFormat.mm, double.infinity, marginAll: 4 * PdfPageFormat.mm),
    onLayout: (_) => doc.save(),
  );
}
