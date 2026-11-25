import 'dart:math';

import 'package:flutter/material.dart';

/// Gráfico de barras simples (sem dependências externas).
class SimpleBarChart extends StatelessWidget {
  const SimpleBarChart({
    super.key,
    required this.labels,
    required this.values,
    required this.color,
    required this.format,
    this.height = 200,
  });

  final List<String> labels;
  final List<double> values;
  final Color color;
  final String Function(double) format;
  final double height;

  @override
  Widget build(BuildContext context) {
    final maxV = values.fold<double>(0, max);
    final barArea = height - 22;
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Tooltip(
                      message: '${labels[i]}: ${format(values[i])}',
                      child: Container(
                        height: maxV == 0
                            ? 2
                            : max(2.0, (values[i] / maxV) * barArea),
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(6)),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [color, color.withAlpha(70)],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      labels[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Duas séries lado a lado (ex.: entradas x saídas).
class DualBarChart extends StatelessWidget {
  const DualBarChart({
    super.key,
    required this.labels,
    required this.a,
    required this.b,
    required this.colorA,
    required this.colorB,
    required this.format,
    this.height = 200,
  });

  final List<String> labels;
  final List<double> a;
  final List<double> b;
  final Color colorA;
  final Color colorB;
  final String Function(double) format;
  final double height;

  @override
  Widget build(BuildContext context) {
    final maxV = [...a, ...b].fold<double>(0, max);
    final barArea = height - 22;
    double h(double v) => maxV == 0 ? 2.0 : max(2.0, (v / maxV) * barArea);

    Widget bar(double v, Color c, String tip) => Expanded(
          child: Tooltip(
            message: tip,
            child: Container(
              height: h(v),
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: c,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ),
          ),
        );

    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        bar(a[i], colorA, 'Entradas ${labels[i]}: ${format(a[i])}'),
                        bar(b[i], colorB, 'Saídas ${labels[i]}: ${format(b[i])}'),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(labels[i],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Barras horizontais com rótulo (ex.: vendas por categoria).
class HBarList extends StatelessWidget {
  const HBarList({
    super.key,
    required this.labels,
    required this.values,
    required this.color,
    required this.format,
  });

  final List<String> labels;
  final List<double> values;
  final Color color;
  final String Function(double) format;

  @override
  Widget build(BuildContext context) {
    final maxV = values.fold<double>(0, max);
    return Column(
      children: [
        for (var i = 0; i < values.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [Text(labels[i]), Text(format(values[i]))],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: maxV == 0 ? 0 : values[i] / maxV,
                    minHeight: 10,
                    color: color,
                    backgroundColor: Colors.white12,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
