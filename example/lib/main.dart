import 'package:flutter/material.dart';
import 'package:media_picker/media_picker.dart';

void main() {
  runApp(const MediaCompressorDemoApp());
}

class MediaCompressorDemoApp extends StatelessWidget {
  const MediaCompressorDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'media_picker example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1A73E8)),
        useMaterial3: true,
      ),
      home: const DemoHomePage(),
    );
  }
}

class DemoHomePage extends StatefulWidget {
  const DemoHomePage({super.key});

  @override
  State<DemoHomePage> createState() => _DemoHomePageState();
}

class _DemoHomePageState extends State<DemoHomePage> {
  final _video = VideoCompressor();
  String _log = 'Ready';
  double _progress = 0;

  Future<void> _pickAndCompressImages() async {
    final picked = await MediaPicker.pick(
      context,
      type: MediaPickType.image,
      maxCount: 6,
    );
    if (picked.isEmpty) return;
    setState(() => _log = 'Compressing ${picked.length} image(s)…');
    final buf = StringBuffer();
    for (final item in picked) {
      final full = await ImageCompressor.compressFile(
        item.path,
        options: MediaCompressPresets.chatImage,
      );
      final thumb = await ImageCompressor.compressFile(
        item.path,
        options: MediaCompressPresets.chatThumb,
      );
      buf.writeln(
        '${item.name ?? item.path}\n'
        '  full ${full.width}x${full.height} ${(full.size / 1024).toStringAsFixed(1)}KB\n'
        '  thumb ${thumb.width}x${thumb.height} ${(thumb.size / 1024).toStringAsFixed(1)}KB',
      );
    }
    setState(() => _log = buf.toString());
  }

  Future<void> _pickAndCompressVideo() async {
    final picked = await MediaPicker.pick(
      context,
      type: MediaPickType.video,
      maxCount: 1,
    );
    if (picked.isEmpty) return;
    final src = picked.first;
    setState(() {
      _log = 'Compressing video…';
      _progress = 0;
    });
    try {
      final result = await _video.compress(
        inputPath: src.path,
        options: MediaCompressPresets.chatVideo,
        onProgress: (p) => setState(() => _progress = p),
      );
      final poster = await _video.extractPoster(result.path, maxSide: 512);
      setState(() {
        _log =
            'Video done\n'
            '  in ${(result.originalSize / 1024 / 1024).toStringAsFixed(2)}MB\n'
            '  out ${(result.size / 1024 / 1024).toStringAsFixed(2)}MB\n'
            '  path ${result.path}\n'
            '  poster ${poster?.length ?? 0} bytes';
      });
    } catch (e) {
      setState(() => _log = 'Video failed: $e');
    }
  }

  @override
  void dispose() {
    _video.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('media_picker')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(
              onPressed: _pickAndCompressImages,
              child: const Text('Pick & compress images'),
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: _pickAndCompressVideo,
              child: const Text('Pick & compress video'),
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _progress <= 0 ? null : _progress),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  _log,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
