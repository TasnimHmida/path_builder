import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:io';

void main() {
  runApp(const MyApp());
}

class PathData {
  List<Offset> points;
  List<Offset?> controlPointsIn;
  List<Offset?> controlPointsOut;

  PathData()
      : points = [],
        controlPointsIn = [],
        controlPointsOut = [];

  PathData copy() {
    PathData newPath = PathData();
    newPath.points = List.from(points);
    newPath.controlPointsIn = controlPointsIn
        .map((cp) => cp != null ? Offset(cp.dx, cp.dy) : null)
        .toList();
    newPath.controlPointsOut = controlPointsOut
        .map((cp) => cp != null ? Offset(cp.dx, cp.dy) : null)
        .toList();
    return newPath;
  }

  String toSvgPath() {
    if (points.isEmpty) return '';

    String svgPath = 'M ${points.first.dx} ${points.first.dy} ';

    for (int i = 0; i < points.length - 1; i++) {
      Offset controlOut = controlPointsOut[i] ?? points[i];
      Offset controlIn = controlPointsIn[i + 1] ?? points[i + 1];
      Offset endPoint = points[i + 1];

      svgPath +=
          'C ${controlOut.dx} ${controlOut.dy}, ${controlIn.dx} ${controlIn.dy}, ${endPoint.dx} ${endPoint.dy} ';
    }

    return svgPath.trim();
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  List<PathData> paths = [];
  int? selectedPathIndex;
  int? selectedPointIndex;
  int? selectedControlPointIndex;
  bool isDrawing = true;
  bool isPenActive = true;
  Offset? currentPoint;
  int? adjustingControlPointIndex;
  Offset? tempControlPoint;
  Offset? startPoint;
  List<List<PathData>> undoStack = [];
  List<List<PathData>> redoStack = [];
  List<SvgPicture> importedSvgs = [];

  @override
  void initState() {
    super.initState();
    paths.add(PathData());
  }

  void pushToUndoStack() {
    undoStack.add(copyPaths(paths));
    redoStack.clear();
  }

  List<PathData> copyPaths(List<PathData> original) {
    return original.map((path) => path.copy()).toList();
  }

  void undo() {
    if (undoStack.isNotEmpty) {
      setState(() {
        redoStack.add(copyPaths(paths));
        paths = undoStack.removeLast();
        selectedPathIndex = null;
        selectedPointIndex = null;
        selectedControlPointIndex = null;
        currentPoint = null;
      });
    }
  }

  void redo() {
    if (redoStack.isNotEmpty) {
      setState(() {
        undoStack.add(copyPaths(paths));
        paths = redoStack.removeLast();
        selectedPathIndex = null;
        selectedPointIndex = null;
        selectedControlPointIndex = null;
        currentPoint = null;
      });
    }
  }

  String ensureSvgDimensions(String svgContent) {
    if (!svgContent.contains('viewBox')) {
      svgContent = svgContent.replaceFirst(
        '<svg ',
        '<svg viewBox="0 0 100 100" ',
      );
    }
    return svgContent;
  }

  String generateSvg() {
    String svgHeader = '''
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<svg xmlns="http
''';

    String svgFooter = '</svg>';

    String svgContent = svgHeader;

    for (PathData pathData in paths) {
      if (pathData.points.isEmpty) continue;

      String pathSvg = '''
  <path d="${pathData.toSvgPath()}" stroke="black" stroke-width="2" fill="none" />
''';
      svgContent += pathSvg;
    }

    svgContent += svgFooter;

    return svgContent;
  }

  Future<void> exportAsSvg() async {
    String svgString = generateSvg();

    String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: 'Save SVG',
      fileName: 'drawing.svg',
      type: FileType.custom,
      allowedExtensions: ['svg'],
    );

    if (outputFile != null) {
      try {
        final file = File(outputFile);
        await file.writeAsString(svgString);
      } catch (e) {
        print(e);
      }
    }
  }

  Future<void> importSvg() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['svg'],
      dialogTitle: 'Import SVG',
    );

    if (result != null && result.files.single.path != null) {
      String filePath = result.files.single.path!;
      try {
        String svgContent = await File(filePath).readAsString();

        final svgContentWithDimensions = ensureSvgDimensions(svgContent);

        final svgWidget = SvgPicture.string(
          svgContentWithDimensions,
          width: MediaQuery.of(context).size.width,
          height: MediaQuery.of(context).size.height,
          fit: BoxFit.contain,
        );

        setState(() {
          importedSvgs.add(svgWidget);
        });
      } catch (e) {
        print(e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Desktop Drawing',
      home: Scaffold(
        floatingActionButton:FloatingActionButton(
          child: Icon(isPenActive ? Icons.brush : Icons.edit),
          onPressed: () {
          setState(() {
            isPenActive = true;
          });
        },
        ) ,
        appBar: AppBar(
          title: const Text('Flutter Desktop Drawing'),
          actions: [
            IconButton(
              icon: const Icon(Icons.undo),
              onPressed: undoStack.isNotEmpty ? undo : null,
              tooltip: 'Undo',
            ),
            IconButton(
              icon: const Icon(Icons.redo),
              onPressed: redoStack.isNotEmpty ? redo : null,
              tooltip: 'Redo',
            ),
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: (paths.isNotEmpty &&
                      paths.any((path) => path.points.isNotEmpty))
                  ? exportAsSvg
                  : null,
              tooltip: 'Export as SVG',
            ),
            IconButton(
              icon: const Icon(Icons.import_export),
              onPressed: importSvg,
              tooltip: 'Import SVG',
            ),
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                setState(() {
                  pushToUndoStack();
                  paths.clear();
                  isDrawing = true;
                  paths.add(PathData());
                  currentPoint = null;
                });
              },
              tooltip: 'Clear Canvas',
            ),
          ],
        ),
        body: MouseRegion(
          onHover: (details) {
            if (isDrawing &&
                isPenActive &&
                paths.isNotEmpty &&
                paths.last.points.isNotEmpty) {
              setState(() {
                currentPoint = details.localPosition;
              });
            } else {
              setState(() {
                currentPoint = null;
              });
            }
          },
          child: GestureDetector(
            onTapDown: (details) {
              if (!isDrawing) {
                setState(() {
                  isDrawing = true;
                  pushToUndoStack();
                  paths.add(PathData());
                  currentPoint = null;
                });
                return;
              }

              selectPointOrAddNew(details.localPosition);
            },
            onPanUpdate: (details) {
              if (selectedPathIndex != null) {
                if (selectedPointIndex != null) {
                  setState(() {
                    pushToUndoStack();
                    paths[selectedPathIndex!].points[selectedPointIndex!] +=
                        details.delta;

                    Offset delta = details.delta;

                    if (paths[selectedPathIndex!]
                            .controlPointsIn[selectedPointIndex!] !=
                        null) {
                      paths[selectedPathIndex!]
                              .controlPointsIn[selectedPointIndex!] =
                          paths[selectedPathIndex!]
                                  .controlPointsIn[selectedPointIndex!]! +
                              delta;
                    }
                    if (paths[selectedPathIndex!]
                            .controlPointsOut[selectedPointIndex!] !=
                        null) {
                      paths[selectedPathIndex!]
                              .controlPointsOut[selectedPointIndex!] =
                          paths[selectedPathIndex!]
                                  .controlPointsOut[selectedPointIndex!]! +
                              delta;
                    }
                  });
                } else if (selectedControlPointIndex != null) {
                  setState(() {
                    pushToUndoStack();

                    Offset anchorPoint = paths[selectedPathIndex!]
                        .points[selectedControlPointIndex!];
                    Offset controlPoint = paths[selectedPathIndex!]
                        .controlPointsOut[selectedControlPointIndex!]!;
                    Offset newControlPoint = controlPoint + details.delta;

                    Offset vector = newControlPoint - anchorPoint;

                    paths[selectedPathIndex!]
                            .controlPointsOut[selectedControlPointIndex!] =
                        newControlPoint;
                    paths[selectedPathIndex!]
                            .controlPointsIn[selectedControlPointIndex!] =
                        anchorPoint - vector;
                  });
                }
              }
            },
            onLongPressStart: (details) {
              if (isDrawing &&
                  paths.isNotEmpty &&
                  paths.last.points.isNotEmpty) {
                setState(() {
                  pushToUndoStack();

                  startPoint = paths.last.points.last;
                  tempControlPoint = details.localPosition;
                });
              }
            },
            onLongPressMoveUpdate: (details) {
              if (isDrawing && paths.isNotEmpty && startPoint != null) {
                setState(() {
                  pushToUndoStack();

                  tempControlPoint = details.localPosition;

                  PathData currentPath = paths.last;
                  int lastPointIndex = currentPath.points.length - 1;
                  currentPath.controlPointsOut[lastPointIndex] =
                      tempControlPoint;
                });
              }
            },
            onLongPressEnd: (details) {
              if (isDrawing &&
                  paths.isNotEmpty &&
                  startPoint != null &&
                  tempControlPoint != null) {
                setState(() {
                  startPoint = null;
                  tempControlPoint = null;
                });
              }
            },
            onDoubleTap: () {
              setState(() {
                isDrawing = false;
                currentPoint = null;
                isPenActive = false;
              });
            },
            child: Container(
              height: double.infinity,
              width: double.infinity,
              color: Colors.blue[100],
              child: Stack(
                children: [
                  ...importedSvgs
                      .map((svg) => Positioned.fill(child: svg))
                      .toList(),
                  CustomPaint(
                    painter: PathPainter(
                      paths: paths,
                      isDrawing: isDrawing,
                      currentPoint: currentPoint,
                    ),
                    size: Size.infinite,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void selectPointOrAddNew(Offset position) {
    const double proximityThreshold = 10.0;

    for (int p = 0; p < paths.length; p++) {
      for (int i = 0; i < paths[p].points.length; i++) {
        if ((paths[p].points[i] - position).distance < proximityThreshold) {
          setState(() {
            selectedPathIndex = p;
            selectedPointIndex = i;
            selectedControlPointIndex = null;
          });
          return;
        }
      }

      for (int i = 0; i < paths[p].controlPointsOut.length; i++) {
        if (paths[p].controlPointsOut[i] != null &&
            (paths[p].controlPointsOut[i]! - position).distance <
                proximityThreshold) {
          setState(() {
            selectedPathIndex = p;
            selectedControlPointIndex = i;
            selectedPointIndex = null;
          });
          return;
        }
      }
    }

    if (isDrawing && isPenActive && paths.isNotEmpty) {
      setState(() {
        pushToUndoStack();
        PathData currentPath = paths.last;
        currentPath.points.add(position);
        currentPath.controlPointsIn.add(position - const Offset(30, 0));
        currentPath.controlPointsOut.add(position + const Offset(30, 0));
        selectedPathIndex = paths.length - 1;
        selectedPointIndex = currentPath.points.length - 1;
        selectedControlPointIndex = null;
      });
    }
  }
}

class PathPainter extends CustomPainter {
  final List<PathData> paths;
  final bool isDrawing;
  final Offset? currentPoint;

  PathPainter({
    required this.paths,
    required this.isDrawing,
    required this.currentPoint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    Paint pathPaint = Paint()
      ..color = isDrawing ? Colors.grey : Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    Paint pointPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.fill;

    Paint controlPaint = Paint()
      ..color = Colors.grey
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    Paint controlDotPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.fill;

    for (int p = 0; p < paths.length; p++) {
      PathData pathData = paths[p];
      if (pathData.points.isEmpty) continue;

      Path path = Path()
        ..moveTo(pathData.points.first.dx, pathData.points.first.dy);

      for (int i = 0; i < pathData.points.length - 1; i++) {
        Offset controlIn =
            pathData.controlPointsIn[i + 1] ?? pathData.points[i];
        Offset controlOut =
            pathData.controlPointsOut[i] ?? pathData.points[i + 1];

        path.cubicTo(
          controlOut.dx,
          controlOut.dy,
          controlIn.dx,
          controlIn.dy,
          pathData.points[i + 1].dx,
          pathData.points[i + 1].dy,
        );

        if (isDrawing) {
          if (pathData.controlPointsOut[i] != null) {
            canvas.drawLine(pathData.points[i], pathData.controlPointsOut[i]!,
                controlPaint);
            canvas.drawCircle(
                pathData.controlPointsOut[i]!, 4.0, controlDotPaint);
          }

          if (pathData.controlPointsIn[i + 1] != null) {
            canvas.drawLine(pathData.points[i + 1],
                pathData.controlPointsIn[i + 1]!, controlPaint);
            canvas.drawCircle(
                pathData.controlPointsIn[i + 1]!, 4.0, controlDotPaint);
          }
        }
      }

      canvas.drawPath(path, pathPaint);

      if (isDrawing) {
        for (Offset point in pathData.points) {
          canvas.drawCircle(point, 5.0, pointPaint);
        }
      }
    }

    if (isDrawing &&
        paths.isNotEmpty &&
        paths.last.points.isNotEmpty &&
        currentPoint != null) {
      PathData currentPath = paths.last;
      Offset lastPoint = currentPath.points.last;
      Offset controlOut =
          currentPath.controlPointsOut.last ?? lastPoint + const Offset(30, 0);
      Offset controlIn = currentPoint! - const Offset(30, 0);

      Path tempPath = Path()
        ..moveTo(lastPoint.dx, lastPoint.dy)
        ..cubicTo(
          controlOut.dx,
          controlOut.dy,
          controlIn.dx,
          controlIn.dy,
          currentPoint!.dx,
          currentPoint!.dy,
        );

      canvas.drawPath(tempPath, pathPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
