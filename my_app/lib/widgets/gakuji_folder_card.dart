import 'package:flutter/material.dart';

class GakujiFolderCard extends StatelessWidget {
  final String title;
  final VoidCallback onTap;

  const GakujiFolderCard({
    super.key,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 0,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: CustomPaint(
            painter: const _GakujiFolderCardPainter(),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 34, 10, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 19,
                    height: 1.05,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GakujiFolderCardPainter extends CustomPainter {
  const _GakujiFolderCardPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final backPaint = Paint()
      ..color = const Color(0xFFF08B32)
      ..style = PaintingStyle.fill;

    final frontPaint = Paint()
      ..color = const Color(0xFFFFCF4D)
      ..style = PaintingStyle.fill;

    final backPath = Path()
      ..moveTo(size.width * 0.18, 0)
      ..lineTo(size.width - 18, 0)
      ..quadraticBezierTo(size.width, 0, size.width, 18)
      ..lineTo(size.width, size.height - 20)
      ..quadraticBezierTo(
        size.width,
        size.height,
        size.width - 20,
        size.height,
      )
      ..lineTo(20, size.height)
      ..quadraticBezierTo(0, size.height, 0, size.height - 20)
      ..lineTo(0, 18)
      ..quadraticBezierTo(0, 0, 18, 0)
      ..close();

    final frontPath = Path()
      ..moveTo(0, size.height * 0.28)
      ..lineTo(size.width * 0.44, size.height * 0.28)
      ..quadraticBezierTo(
        size.width * 0.50,
        size.height * 0.28,
        size.width * 0.53,
        size.height * 0.36,
      )
      ..lineTo(size.width - 18, size.height * 0.36)
      ..quadraticBezierTo(
        size.width,
        size.height * 0.36,
        size.width,
        size.height * 0.54,
      )
      ..lineTo(size.width, size.height - 20)
      ..quadraticBezierTo(
        size.width,
        size.height,
        size.width - 20,
        size.height,
      )
      ..lineTo(20, size.height)
      ..quadraticBezierTo(0, size.height, 0, size.height - 20)
      ..close();

    canvas.drawPath(backPath, backPaint);
    canvas.drawPath(frontPath, frontPaint);
  }

  @override
  bool shouldRepaint(covariant _GakujiFolderCardPainter oldDelegate) {
    return false;
  }
}