import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:io';

void main() {
  runApp(const MyApp());
}

/// A class representing a single path with its points and control points.
class PathData {
  List<Offset> points;
  List<Offset?> controlPointsIn;
  List<Offset?> controlPointsOut;

  PathData()
      : points = [],
        controlPointsIn = [],
        controlPointsOut = [];

  /// Creates a deep copy of the current PathData instance.
  PathData copy() {
    PathData newPath = PathData();
    newPath.points = List.from(this.points);
    newPath.controlPointsIn = this
        .controlPointsIn
        .map((cp) => cp != null ? Offset(cp.dx, cp.dy) : null)
        .toList();
    newPath.controlPointsOut = this
        .controlPointsOut
        .map((cp) => cp != null ? Offset(cp.dx, cp.dy) : null)
        .toList();
    return newPath;
  }

  /// Converts the PathData to an SVG path string.
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
  // List of all paths drawn on the canvas.
  List<PathData> paths = [];

  // Currently selected path index for dragging.
  int? selectedPathIndex;

  // Currently selected point index within the selected path.
  int? selectedPointIndex;

  // Currently selected control point index within the selected path.
  int? selectedControlPointIndex;

  // Flag to determine if the app is in drawing mode.
  bool isDrawing = true;

  // Current mouse position for dynamic drawing.
  Offset? currentPoint;
  int? adjustingControlPointIndex;
  // New fields to track a control point adjustment during a long press.
  Offset? tempControlPoint;
  Offset? startPoint;
  // Undo and Redo stacks
  List<List<PathData>> undoStack = [];
  List<List<PathData>> redoStack = [];

  // List of imported SVG widgets
  List<SvgPicture> importedSvgs = [];

  @override
  void initState() {
    super.initState();
    // Initialize with a new path.
    paths.add(PathData());
  }

  /// Pushes the current state of paths to the undo stack.
  void pushToUndoStack() {
    undoStack.add(copyPaths(paths));
    // Clear redo stack whenever a new action is performed.
    redoStack.clear();
  }

  /// Copies the list of PathData deeply.
  List<PathData> copyPaths(List<PathData> original) {
    return original.map((path) => path.copy()).toList();
  }

  /// Handles the Undo action.
  void undo() {
    if (undoStack.isNotEmpty) {
      setState(() {
        // Push current state to redo stack.
        redoStack.add(copyPaths(paths));
        // Pop the last state from undo stack and set it as current paths.
        paths = undoStack.removeLast();
        // Deselect any selected elements.
        selectedPathIndex = null;
        selectedPointIndex = null;
        selectedControlPointIndex = null;
        currentPoint = null;
      });
    }
  }

  /// Handles the Redo action.
  void redo() {
    if (redoStack.isNotEmpty) {
      setState(() {
        // Push current state to undo stack.
        undoStack.add(copyPaths(paths));
        // Pop the last state from redo stack and set it as current paths.
        paths = redoStack.removeLast();
        // Deselect any selected elements.
        selectedPathIndex = null;
        selectedPointIndex = null;
        selectedControlPointIndex = null;
        currentPoint = null;
      });
    }
  }

  // Ensure the SVG content has viewBox or width/height attributes.
  String ensureSvgDimensions(String svgContent) {
    if (!svgContent.contains('viewBox')) {
      svgContent = svgContent.replaceFirst(
        '<svg ',
        '<svg viewBox="0 0 100 100" ', // Adjust the viewBox values as needed.
      );
    }
    return svgContent;
  }

  /// Generates the complete SVG content from all paths.
  String generateSvg() {
    // Define the SVG header with a fixed viewBox. Adjust as needed.
    String svgHeader = '''
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<svg xmlns="http://www.w3.org/2000/svg" version="1.1">
''';

    // Define the SVG footer.
    String svgFooter = '</svg>';

    // Initialize the SVG content.
    String svgContent = svgHeader;

    for (PathData pathData in paths) {
      if (pathData.points.isEmpty) continue;

      String pathSvg = '''
  <path d="${pathData.toSvgPath()}" stroke="${isDrawing ? 'red' : 'black'}" stroke-width="2" fill="none" />
''';
      svgContent += pathSvg;
    }

    svgContent += svgFooter;

    return svgContent;
  }

  /// Handles exporting the drawing as an SVG file.
  Future<void> exportAsSvg() async {
    // Generate the SVG string.
    String svgString = generateSvg();

    // Open a save file dialog.
    String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: 'Save SVG',
      fileName: 'drawing.svg',
      type: FileType.custom,
      allowedExtensions: ['svg'],
    );

    if (outputFile != null) {
      try {
        // Write the SVG string to the file.
        final file = File(outputFile);
        await file.writeAsString(svgString);

        // Show a confirmation message.
        // ScaffoldMessenger.of(context).showSnackBar(
        //   SnackBar(content: Text('SVG exported successfully to $outputFile')),
        // );
      } catch (e) {
        print(e);
        // Handle any errors during file writing.
        // ScaffoldMessenger.of(context).showSnackBar(
        //   SnackBar(content: Text('Failed to export SVG: $e')),
        // );
      }
    }
  }

  /// Handles importing an SVG file and adding it to the canvas.
  Future<void> importSvg() async {
    // Open a file picker dialog to select an SVG file.
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['svg'],
      dialogTitle: 'Import SVG',
    );

    if (result != null && result.files.single.path != null) {
      String filePath = result.files.single.path!;
      try {
        // Read the SVG file as a string.
        String svgContent = await File(filePath).readAsString();

        // When creating the SvgPicture widget:
        final svgContentWithDimensions = ensureSvgDimensions(svgContent);

        // Create an SvgPicture widget from the SVG string.
        final svgWidget = SvgPicture.string(
          svgContentWithDimensions,
          width: MediaQuery.of(context).size.width,
          height: MediaQuery.of(context).size.height,
          fit: BoxFit.contain,
        );

        setState(() {
          // Add the imported SVG widget to the list of imported SVGs.
          importedSvgs.add(svgWidget);
        });

        // Optionally, show a confirmation message.
        // ScaffoldMessenger.of(context).showSnackBar(
        //   SnackBar(content: Text('SVG imported successfully from $filePath')),
        // );
      } catch (e) {
        // Handle any errors during file reading or SVG parsing.
        // ScaffoldMessenger.of(context).showSnackBar(
        //   SnackBar(content: Text('Failed to import SVG: $e')),
        // );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Desktop Drawing',
      home: Scaffold(
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
            if (isDrawing && paths.isNotEmpty && paths.last.points.isNotEmpty) {
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
                  // Dragging a point within the selected path.
                  setState(() {
                    pushToUndoStack();
                    paths[selectedPathIndex!].points[selectedPointIndex!] += details.delta;

                    // Move associated control points to maintain relative positions.
                    Offset delta = details.delta;

                    // Adjust control points relative to the moved point.
                    if (paths[selectedPathIndex!].controlPointsIn[selectedPointIndex!] != null) {
                      paths[selectedPathIndex!].controlPointsIn[selectedPointIndex!] =
                          paths[selectedPathIndex!].controlPointsIn[selectedPointIndex!]! + delta;
                    }
                    if (paths[selectedPathIndex!].controlPointsOut[selectedPointIndex!] != null) {
                      paths[selectedPathIndex!].controlPointsOut[selectedPointIndex!] =
                          paths[selectedPathIndex!].controlPointsOut[selectedPointIndex!]! + delta;
                    }
                  });
                } else if (selectedControlPointIndex != null) {
                  // Dragging a control point within the selected path.
                  setState(() {
                    pushToUndoStack();

                    Offset anchorPoint = paths[selectedPathIndex!].points[selectedControlPointIndex!];
                    Offset controlPoint = paths[selectedPathIndex!].controlPointsOut[selectedControlPointIndex!]!;
                    Offset newControlPoint = controlPoint + details.delta;

                    // Calculate the vector between the anchor point and the moved control point.
                    Offset vector = newControlPoint - anchorPoint;

                    // Adjust the opposite control point to maintain symmetry.
                    paths[selectedPathIndex!].controlPointsOut[selectedControlPointIndex!] = newControlPoint;
                    paths[selectedPathIndex!].controlPointsIn[selectedControlPointIndex!] = anchorPoint - vector;
                  });
                }
              }
            },
            onPanEnd: (_) {
              setState(() {
                selectedPathIndex = null;
                selectedPointIndex = null;
                selectedControlPointIndex = null;
                tempControlPoint = null;
                startPoint = null;
              });
            },
            onLongPressStart: (details) {
              if (isDrawing && paths.isNotEmpty && paths.last.points.isNotEmpty) {
                setState(() {
                  pushToUndoStack();

                  // Track the point being adjusted.
                  startPoint = paths.last.points.last;
                  tempControlPoint = details.localPosition;
                });
              }
            },
            onLongPressMoveUpdate: (details) {
              if (isDrawing && paths.isNotEmpty && startPoint != null) {
                setState(() {
                  pushToUndoStack();

                  // Update the temporary control point based on drag position.
                  tempControlPoint = details.localPosition;

                  // Update the outgoing control point for the last added point.
                  PathData currentPath = paths.last;
                  int lastPointIndex = currentPath.points.length - 1;
                  currentPath.controlPointsOut[lastPointIndex] = tempControlPoint;
                });
              }
            },
            onLongPressEnd: (details) {
              if (isDrawing && paths.isNotEmpty && startPoint != null && tempControlPoint != null) {
                setState(() {
                  // Reset temporary variables.
                  startPoint = null;
                  tempControlPoint = null;
                });
              }
            },
            onDoubleTap: () {
              setState(() {
                isDrawing = false;
                currentPoint = null;
              });
            },
            child: Container(
              height: double.infinity,
              width: double.infinity,
              color: Colors.blue[100],
              child: Stack(
                children: [
                  // Render all imported SVGs
                  ...importedSvgs
                      .map((svg) => Positioned.fill(child: svg))
                      .toList(),

                  // Render the user-drawn paths
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

  /// Handles selection of existing points/control points or adds a new point to the current path.
  void selectPointOrAddNew(Offset position) {
    const double proximityThreshold = 10.0;

    // Iterate through all paths to find if a point or control point is selected.
    for (int p = 0; p < paths.length; p++) {
      // Check for point selection.
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

      // Check for control point selection.
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

    // If no point or control point is selected, add a new point to the last path.
    if (isDrawing && paths.isNotEmpty) {
      setState(() {
        pushToUndoStack();
        PathData currentPath = paths.last;
        currentPath.points.add(position);
        // Initialize control points extending horizontally by default.
        currentPath.controlPointsIn.add(position - const Offset(30, 0));
        currentPath.controlPointsOut.add(position + const Offset(30, 0));
        selectedPathIndex = paths.length - 1;
        selectedPointIndex = currentPath.points.length - 1;
        selectedControlPointIndex = null;
      });
    }
  }
}

/// CustomPainter to draw all paths, points, and control arrows.
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
    // Paint for the main paths.
    Paint pathPaint = Paint()
      ..color = isDrawing ? Colors.grey : Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // Paint for the points.
    Paint pointPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.fill;

    // Paint for the control arrows (lines).
    Paint controlPaint = Paint()
      ..color = Colors.grey
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Paint for the control point dots.
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
          // Draw outgoing control arrow from current point.
          if (pathData.controlPointsOut[i] != null) {
            canvas.drawLine(pathData.points[i], pathData.controlPointsOut[i]!,
                controlPaint);
            canvas.drawCircle(
                pathData.controlPointsOut[i]!, 4.0, controlDotPaint);
          }

          // Draw incoming control arrow to next point.
          if (pathData.controlPointsIn[i + 1] != null) {
            canvas.drawLine(pathData.points[i + 1],
                pathData.controlPointsIn[i + 1]!, controlPaint);
            canvas.drawCircle(
                pathData.controlPointsIn[i + 1]!, 4.0, controlDotPaint);
          }
        }
      }

      // Draw the main path.
      canvas.drawPath(path, pathPaint);

      if (isDrawing) {
        // Draw each point as a small circle.
        for (Offset point in pathData.points) {
          canvas.drawCircle(point, 5.0, pointPaint);
        }
      }
    }

    // Draw the dynamic path following the mouse (only for the last path).
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
