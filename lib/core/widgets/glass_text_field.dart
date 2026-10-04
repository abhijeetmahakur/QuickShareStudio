import 'package:flutter/material.dart';
import '../constants.dart';

class GlassTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String hintText;
  final String? helperText;
  final String? errorText;
  final IconData prefixIcon;
  final int maxLength;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSubmitted;
  final FocusNode? focusNode;

  const GlassTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hintText = 'My Laptop',
    this.helperText,
    this.errorText,
    this.prefixIcon = Icons.laptop_mac_rounded,
    this.maxLength = 32,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
  });

  @override
  State<GlassTextField> createState() => _GlassTextFieldState();
}

class _GlassTextFieldState extends State<GlassTextField> {
  late final FocusNode _focusNode;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    setState(() {
      _isFocused = _focusNode.hasFocus;
    });
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _focusNode.dispose();
    } else {
      _focusNode.removeListener(_handleFocusChange);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasError = widget.errorText != null && widget.errorText!.isNotEmpty;
    final hasText = widget.controller.text.isNotEmpty;

    final borderColor = hasError
        ? AppColors.error
        : (_isFocused ? AppColors.limeGreen : AppColors.glassBorder);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              widget.label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.white,
                letterSpacing: 0.2,
              ),
            ),
            Text(
              '${widget.controller.text.length}/${widget.maxLength}',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                color: widget.controller.text.length >= widget.maxLength
                    ? AppColors.warning
                    : AppColors.softGray.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: AppColors.glassInputBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: borderColor,
              width: _isFocused ? 1.8 : 1.0,
            ),
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: hasError
                          ? AppColors.error.withValues(alpha: 0.25)
                          : AppColors.limeGreen.withValues(alpha: 0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Icon(
                widget.prefixIcon,
                size: 22,
                color: _isFocused ? AppColors.limeGreen : AppColors.softGray,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focusNode,
                  maxLength: widget.maxLength,
                  buildCounter: (
                    context, {
                    required currentLength,
                    required isFocused,
                    maxLength,
                  }) =>
                      null, // Hide default counter
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.white,
                  ),
                  cursorColor: AppColors.limeGreen,
                  decoration: InputDecoration(
                    hintText: widget.hintText,
                    hintStyle: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 15,
                      color: AppColors.softGray.withValues(alpha: 0.45),
                    ),
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onChanged: (val) {
                    setState(() {});
                    widget.onChanged?.call(val);
                  },
                  onSubmitted: (_) => widget.onSubmitted?.call(),
                ),
              ),
              if (hasText)
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: AppColors.softGray,
                  tooltip: 'Clear input',
                  onPressed: () {
                    widget.controller.clear();
                    setState(() {});
                    widget.onChanged?.call('');
                  },
                ),
            ],
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.error_outline_rounded, size: 14, color: AppColors.error),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.errorText!,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: AppColors.error,
                  ),
                ),
              ),
            ],
          ),
        ] else if (widget.helperText != null) ...[
          const SizedBox(height: 6),
          Text(
            widget.helperText!,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              color: AppColors.softGray.withValues(alpha: 0.7),
            ),
          ),
        ],
      ],
    );
  }
}
