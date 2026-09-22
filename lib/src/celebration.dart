part of '../main.dart';

class CelebrationOverlay extends StatefulWidget {
  const CelebrationOverlay({
    super.key,
    required this.title,
    required this.message,
    required this.onDismiss,
  });

  final String title;
  final String message;
  final VoidCallback onDismiss;

  @override
  State<CelebrationOverlay> createState() => _CelebrationOverlayState();
}

class _CelebrationOverlayState extends State<CelebrationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  )..forward();

  final random = math.Random(8);

  @override
  void initState() {
    super.initState();
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) widget.onDismiss();
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        onTap: widget.onDismiss,
        child: ColoredBox(
          color: Colors.black.withValues(alpha: .18),
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, child) {
              return CustomPaint(
                painter: FireworksPainter(
                    progress: controller.value, random: random),
                child: Center(child: child),
              );
            },
            child: Card(
              margin: const EdgeInsets.symmetric(horizontal: 44),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('🎉', style: TextStyle(fontSize: 48)),
                    const SizedBox(height: 8),
                    Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.message,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DailyMemoryReviewDialog extends StatelessWidget {
  const DailyMemoryReviewDialog({
    super.key,
    required this.memories,
    required this.today,
  });

  final List<DailyMemoryGroup> memories;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    int? lastYear;
    for (var index = 0; index < memories.length; index++) {
      final memory = memories[index];
      if (memory.year != lastYear) {
        lastYear = memory.year;
        children.add(
          Padding(
            padding: EdgeInsets.only(top: index == 0 ? 0 : 18, bottom: 8),
            child: Text(
              '${memory.year}年 · ${today.year - memory.year}年前',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
        );
      }
      children.add(_memoryGroup(context, index, memory));
    }

    final screenHeight = MediaQuery.of(context).size.height;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: screenHeight * .82,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    foregroundColor:
                        Theme.of(context).colorScheme.onPrimaryContainer,
                    child: const Icon(Icons.history_outlined),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '几年前的今天',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text('看看过去的今天发生了什么'),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: '关闭',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 8),
                  children: children,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '这些照片来自手机相册中已经记录的真实回忆。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _memoryGroup(
    BuildContext context,
    int groupIndex,
    DailyMemoryGroup memory,
  ) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .42),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${memory.cardTitle} · ${memory.groupTitle}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${memory.photos.length} 张',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: memory.photos.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
                childAspectRatio: 1,
              ),
              itemBuilder: (context, photoIndex) {
                final photo = memory.photos[photoIndex];
                return GestureDetector(
                  onTap: () => _openPhotoPreview(
                    context,
                    groupIndex,
                    photoIndex,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _buildPhotoImage(photo),
                        Positioned(
                          left: 4,
                          right: 4,
                          bottom: 4,
                          child: Text(
                            '${photo.captureDate.month}月${photo.captureDate.day}日',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              shadows: [
                                Shadow(blurRadius: 4, color: Colors.black),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openPhotoPreview(
    BuildContext context,
    int groupIndex,
    int photoIndex,
  ) {
    final items = <PhotoPreviewItem>[];
    var initialPage = 0;
    for (var currentGroupIndex = 0;
        currentGroupIndex < memories.length;
        currentGroupIndex++) {
      final group = memories[currentGroupIndex];
      final groupTitle =
          '${group.year}年 · ${group.cardTitle} · ${group.groupTitle}';
      for (var currentPhotoIndex = 0;
          currentPhotoIndex < group.photos.length;
          currentPhotoIndex++) {
        if (currentGroupIndex == groupIndex &&
            currentPhotoIndex == photoIndex) {
          initialPage = items.length;
        }
        items.add(
          PhotoPreviewItem(
            groupTitle: groupTitle,
            photo: group.photos[currentPhotoIndex],
          ),
        );
      }
    }
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .92),
      builder: (_) => PhotoPreviewDialog(
        items: items,
        initialPage: initialPage,
      ),
    );
  }
}

String dateKey(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

class FireworksPainter extends CustomPainter {
  FireworksPainter({required this.progress, required this.random});

  final double progress;
  final math.Random random;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final centers = [
      Offset(size.width * .22, size.height * .25),
      Offset(size.width * .78, size.height * .22),
      Offset(size.width * .5, size.height * .12),
    ];
    final colors = [
      Colors.pink,
      Colors.amber,
      Colors.cyan,
      Colors.deepPurple,
      Colors.green
    ];
    for (var burst = 0; burst < centers.length; burst++) {
      final center = centers[burst];
      final radius = 25 + progress * 110;
      for (var particle = 0; particle < 18; particle++) {
        final angle = particle * math.pi * 2 / 18;
        final distance = radius * (0.55 + (particle % 4) * .12);
        final point =
            center + Offset(math.cos(angle), math.sin(angle)) * distance;
        paint.color = colors[(particle + burst) % colors.length]
            .withValues(alpha: 1 - progress);
        canvas.drawCircle(point, 4 * (1 - progress * .45), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant FireworksPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
