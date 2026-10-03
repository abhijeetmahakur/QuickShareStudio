import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../data/models/screenshot_item.dart';

class SampleScreenshotGenerator {
  /// Generates a set of realistic computer-lab screenshots for instant testing and demonstration
  static Future<List<ScreenshotItem>> generateLabSamples() async {
    final samples = <ScreenshotItem>[
      await _createSyntheticScreenshot(
        title: 'Java_Practical_01_Main.java',
        subtitle: 'public class StudentRegistration { ... }',
        tag: 'JAVA CODE',
        primaryColor: const Color(0xFF1E293B),
        accentColor: const Color(0xFF38BDF8),
        codeLines: [
          '// Experiment 1: Student Record Database System',
          'import java.util.Scanner;',
          '',
          'public class StudentRecord {',
          '    private String studentId;',
          '    private String name;',
          '    private double gpa;',
          '',
          '    public StudentRecord(String id, String n, double g) {',
          '        this.studentId = id;',
          '        this.name = n;',
          '        this.gpa = g;',
          '    }',
          '}',
        ],
      ),
      await _createSyntheticScreenshot(
        title: 'Terminal_Compile_Output.log',
        subtitle: '\$ javac StudentRecord.java && java StudentRecord',
        tag: 'TERMINAL',
        primaryColor: const Color(0xFF0F172A),
        accentColor: const Color(0xFF4ADE80),
        codeLines: [
          '\$ javac StudentRecord.java',
          '\$ java StudentRecord',
          '--- Running Test Suite [3/3 Passed] ---',
          '[INFO] Initializing In-Memory Data Store...',
          '[PASS] Test Case 1: Student Insert (ID: CS2026-042)',
          '[PASS] Test Case 2: Validation Range Check (GPA >= 0.0)',
          '[PASS] Test Case 3: Duplicate Record Prevention',
          'Process finished with exit code 0',
        ],
      ),
      await _createSyntheticScreenshot(
        title: 'Python_DataStructures_Lab2.py',
        subtitle: 'class BinarySearchTree: def insert(self, val)...',
        tag: 'PYTHON',
        primaryColor: const Color(0xFF18181B),
        accentColor: const Color(0xFFFBBF24),
        codeLines: [
          '# QuickShare Lab Demonstration',
          'class TreeNode:',
          '    def __init__(self, key):',
          '        self.left = None',
          '        self.right = None',
          '        self.val = key',
          '',
          'def inorder_traversal(root):',
          '    return inorder_traversal(root.left) + [root.val] if root else []',
        ],
      ),
      await _createSyntheticScreenshot(
        title: 'Network_Socket_Server.cpp',
        subtitle: 'int server_fd = socket(AF_INET, SOCK_STREAM, 0);',
        tag: 'C++ NETWORKING',
        primaryColor: const Color(0xFF172554),
        accentColor: const Color(0xFFA78BFA),
        codeLines: [
          '#include <iostream>',
          '#include <sys/socket.h>',
          '#include <netinet/in.h>',
          '',
          'int main() {',
          '    int server_fd = socket(AF_INET, SOCK_STREAM, 0);',
          '    std::cout << "[SERVER] Listening on port 8088..." << std::endl;',
          '    return 0;',
          '}',
        ],
      ),
      await _createSyntheticScreenshot(
        title: 'SQL_Query_Execution_Result.png',
        subtitle: 'SELECT * FROM students WHERE grade >= 90;',
        tag: 'DATABASE SQL',
        primaryColor: const Color(0xFF1F2937),
        accentColor: const Color(0xFFF472B6),
        codeLines: [
          '-- Query: High Performing Students Report',
          'SELECT student_id, first_name, course, semester_gpa',
          'FROM university_enrolments',
          'WHERE semester_gpa >= 3.85',
          'ORDER BY semester_gpa DESC LIMIT 5;',
          '+------------+------------+---------------+--------------+',
          '| CS-9912    | Sophia     | Computer Sci  | 4.00         |',
          '| CS-8841    | Alex       | AI & Data Sci | 3.96         |',
          '+------------+------------+---------------+--------------+',
        ],
      ),
      await _createSyntheticScreenshot(
        title: 'Web_Frontend_Dashboard.tsx',
        subtitle: 'export function AnalyticsPanel() { ... }',
        tag: 'REACT / TS',
        primaryColor: const Color(0xFF111827),
        accentColor: const Color(0xFF34D399),
        codeLines: [
          'import React, { useState } from "react";',
          'export const StatusWidget = () => {',
          '  const [connected, setConnected] = useState(true);',
          '  return <div className="badge">{connected ? "Online" : "Offline"}</div>;',
          '};',
        ],
      ),
    ];
    return samples;
  }

  static Future<ScreenshotItem> _createSyntheticScreenshot({
    required String title,
    required String subtitle,
    required String tag,
    required Color primaryColor,
    required Color accentColor,
    required List<String> codeLines,
  }) async {
    const width = 1280;
    const height = 720;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 1280, 720));

    // Background fill
    final bgPaint = Paint()..color = primaryColor;
    canvas.drawRect(const Rect.fromLTWH(0, 0, 1280, 720), bgPaint);

    // Window header bar (macOS / IDE style window controls)
    final headerPaint = Paint()..color = const Color(0xFF0F172A).withValues(alpha: 0.8);
    canvas.drawRect(const Rect.fromLTWH(0, 0, 1280, 48), headerPaint);

    // Red, yellow, green window circles
    final redDot = Paint()..color = const Color(0xFFEF4444);
    final yellowDot = Paint()..color = const Color(0xFFF59E0B);
    final greenDot = Paint()..color = const Color(0xFF10B981);
    canvas.drawCircle(const Offset(24, 24), 7, redDot);
    canvas.drawCircle(const Offset(48, 24), 7, yellowDot);
    canvas.drawCircle(const Offset(72, 24), 7, greenDot);

    // Tag badge on right
    final tagPaint = Paint()..color = accentColor.withValues(alpha: 0.2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(width - 180, 12, 160, 26), const Radius.circular(6)),
      tagPaint,
    );

    // Paint Title & Tag
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    textPainter.text = TextSpan(
      text: tag,
      style: TextStyle(color: accentColor, fontSize: 13, fontWeight: FontWeight.bold),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(width - 170 + (140 - textPainter.width) / 2, 16));

    textPainter.text = TextSpan(
      text: title,
      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
    );
    textPainter.layout();
    textPainter.paint(canvas, const Offset(100, 14));

    // Code lines rendering
    var yPos = 80.0;
    for (var i = 0; i < codeLines.length; i++) {
      final line = codeLines[i];

      // Line number
      textPainter.text = TextSpan(
        text: (i + 1).toString().padLeft(2, ' '),
        style: const TextStyle(color: Color(0xFF64748B), fontSize: 18, fontFamily: 'monospace'),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(24, yPos));

      // Code text
      textPainter.text = TextSpan(
        text: line,
        style: TextStyle(
          color: line.startsWith('//') || line.startsWith('#') || line.startsWith('--')
              ? const Color(0xFF64748B)
              : Colors.white.withValues(alpha: 0.95),
          fontSize: 18,
          fontFamily: 'monospace',
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(70, yPos));

      yPos += 32.0;
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(width, height);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();

    return ScreenshotItem(
      name: title,
      bytes: bytes,
      aspectRatio: width / height,
      width: width,
      height: height,
      caption: subtitle,
    );
  }
}
