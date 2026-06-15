// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-16 10:25 UTC-5 (Lima)][desc: Soporta MaterialLocalizations para es_PE/es_ES (historial por fecha)][obj: QuestionnaireScreen]
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../models/cuestionario.dart';
import '../../services/offline_questionnaire_store.dart';
import '../../services/api_service.dart';
import '../../services/questionnaire_sync_manager.dart';

class QuestionnaireScreen extends StatefulWidget {
  const QuestionnaireScreen({
    super.key,
    required this.cuestionario,
    required this.preguntas,
    required this.apiService,
    required this.idPersona,
    required this.idItem,
    this.visitLabel,
  });

  final Cuestionario cuestionario;
  final List<Pregunta> preguntas;
  final ApiService apiService;
  final int idPersona;
  // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-01-22 09:23 UTC-5 (Lima)][desc: Mantiene el item de visita para registrar respuestas por visita][obj: QuestionnaireScreen.idItem]
  final int idItem;
  final String? visitLabel;

  @override
  State<QuestionnaireScreen> createState() => _QuestionnaireScreenState();
}

class _QuestionnaireScreenState extends State<QuestionnaireScreen> {
  final Map<int, TextEditingController> _controllers = {};
  final Map<int, String?> _selectedOptions = {};
  final Map<int, Pregunta> _preguntaPorId = {};
  final List<int> _questionPath = [];
  Pregunta? _rootPregunta;
  int? _currentQuestionId;
  bool _saving = false;
  final OfflineQuestionnaireStore _offlineStore = OfflineQuestionnaireStore();

  @override
  void initState() {
    super.initState();
    for (final pregunta in widget.preguntas) {
      if (_needsTextController(pregunta)) {
        _controllers[pregunta.id] = TextEditingController();
      }
      _preguntaPorId[pregunta.id] = pregunta;
    }
    _rootPregunta = _findRootPregunta(widget.preguntas);
    _currentQuestionId = _rootPregunta?.id;
    if (_currentQuestionId != null) {
      _questionPath.add(_currentQuestionId!);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  bool _needsTextController(Pregunta pregunta) {
    final tipo = pregunta.tipo.toUpperCase();
    return tipo == 'T' || tipo == 'N' || tipo == 'F';
  }

  bool _isRequired(Pregunta pregunta) {
    return pregunta.obligatorio.toUpperCase() == 'S';
  }

  String _formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _answerFor(Pregunta pregunta) {
    final tipo = pregunta.tipo.toUpperCase();
    if (tipo == 'O') {
      return _selectedOptions[pregunta.id] ?? '';
    }
    final controller = _controllers[pregunta.id];
    return controller?.text.trim() ?? '';
  }

  String? _validatePregunta(Pregunta pregunta, String respuesta) {
    if (_isRequired(pregunta) && respuesta.isEmpty) {
      return 'Completa la pregunta: ${pregunta.descripcion}';
    }
    final tipo = pregunta.tipo.toUpperCase();
    if (tipo == 'N' && respuesta.isNotEmpty) {
      final parsed = num.tryParse(respuesta.replaceAll(',', '.'));
      if (parsed == null) {
        return 'Ingresa un numero valido en: ${pregunta.descripcion}';
      }
    }
    return null;
  }

  Future<void> _pickDate(Pregunta pregunta) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null) return;
    final controller = _controllers[pregunta.id];
    if (controller == null) return;
    setState(() => controller.text = _formatDate(picked));
  }

  Pregunta? get _currentQuestion =>
      _currentQuestionId == null ? null : _preguntaPorId[_currentQuestionId!];

  bool get _hasNextQuestion {
    final current = _currentQuestion;
    if (current == null) return false;
    final nextId = _determineNextQuestionId(current);
    return nextId != null;
  }

  bool get _canGoToNext {
    final current = _currentQuestion;
    if (current == null) return false;
    if (_isRequired(current) && _answerFor(current).isEmpty) return false;
    return _determineNextQuestionId(current) != null;
  }

  Future<void> _submit() async {
    if (_saving) return;
    final preguntas = _questionPath
        .map((id) => _preguntaPorId[id])
        .where((p) => p != null)
        .cast<Pregunta>()
        .toList();
    for (final pregunta in preguntas) {
      final respuesta = _answerFor(pregunta);
      final error = _validatePregunta(pregunta, respuesta);
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
        return;
      }
    }

    final respuestas = <RespuestaPayload>[];
    for (final pregunta in preguntas) {
      final respuesta = _answerFor(pregunta);
      if (respuesta.isEmpty) {
        continue;
      }
      respuestas.add(
        RespuestaPayload(
          idPersona: widget.idPersona,
          idCuestionario: widget.cuestionario.id,
          idPregunta: pregunta.id,
          idItem: widget.idItem,
          textoPregunta: pregunta.descripcion,
          respuesta: respuesta,
          estado: 1,
        ),
      );
    }

    setState(() => _saving = true);
    try {
      await _offlineStore.enqueue(
        visitId: widget.idItem,
        cuestionarioId: widget.cuestionario.id,
        respuestas: respuestas,
      );
      GetIt.I<QuestionnaireSyncManager>().triggerNow();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cuestionario guardado para sincronizar.')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar el cuestionario: $e')),
      );
      setState(() => _saving = false);
    }
  }

  Pregunta? _findRootPregunta(List<Pregunta> preguntas) {
    if (preguntas.isEmpty) return null;
    final referenced = <int>{};
    for (final pregunta in preguntas) {
      if (pregunta.idSiguientePregunta != null) {
        referenced.add(pregunta.idSiguientePregunta!);
      }
      for (final opcion in pregunta.opciones) {
        if (opcion.idSiguientePregunta != null) {
          referenced.add(opcion.idSiguientePregunta!);
        }
      }
    }
    final candidates = preguntas
        .where((pregunta) => !referenced.contains(pregunta.id))
        .toList();
    if (candidates.isNotEmpty) {
      candidates.sort((a, b) => a.orden.compareTo(b.orden));
      return candidates.first;
    }
    return preguntas.reduce((a, b) => a.orden <= b.orden ? a : b);
  }

  int? _determineNextQuestionId(Pregunta pregunta) {
    if (pregunta.tipo.toUpperCase() == 'O') {
      final selectedValue = _selectedOptions[pregunta.id];
      if (selectedValue == null || selectedValue.isEmpty) {
        return null;
      }
      Opcion? opcion;
      for (final op in pregunta.opciones) {
        if (_optionValue(op) == selectedValue) {
          opcion = op;
          break;
        }
      }
      if (opcion == null) {
        return pregunta.idSiguientePregunta;
      }
      if (opcion.idSiguientePregunta != null) {
        return opcion.idSiguientePregunta;
      }
    }
    return pregunta.idSiguientePregunta;
  }

  void _prunePathAfterCurrent() {
    if (_currentQuestionId == null) return;
    final currentIndex = _questionPath.indexOf(_currentQuestionId!);
    if (currentIndex < 0) return;
    if (currentIndex < _questionPath.length - 1) {
      final removed = _questionPath.sublist(currentIndex + 1);
      _questionPath.removeRange(currentIndex + 1, _questionPath.length);
      for (final id in removed) {
        _selectedOptions.remove(id);
        _controllers[id]?.clear();
      }
    }
  }

  void _goToNextQuestion() {
    final current = _currentQuestion;
    if (current == null) return;
    final answer = _answerFor(current);
    final error = _validatePregunta(current, answer);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    final nextId = _determineNextQuestionId(current);
    if (nextId == null) return;
    if (!_questionPath.contains(current.id)) {
      _questionPath.add(current.id);
    }
    _prunePathAfterCurrent();
    if (!_questionPath.contains(nextId)) {
      _questionPath.add(nextId);
    }
    setState(() {
      _currentQuestionId = nextId;
    });
  }

  void _goToPreviousQuestion() {
    if (_currentQuestionId == null) return;
    final currentIndex = _questionPath.indexOf(_currentQuestionId!);
    if (currentIndex <= 0) return;
    setState(() {
      _currentQuestionId = _questionPath[currentIndex - 1];
    });
  }

  String _optionValue(Opcion opcion) {
    return (opcion.valor != null && opcion.valor!.isNotEmpty)
        ? opcion.valor!
        : opcion.descripcion;
  }

  Widget _buildPregunta(Pregunta pregunta) {
    final tipo = pregunta.tipo.toUpperCase();
    final required = _isRequired(pregunta);
    final label = required ? '${pregunta.descripcion} *' : pregunta.descripcion;
    final theme = Theme.of(context);

    if (tipo == 'O') {
      if (pregunta.opciones.isEmpty) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            '$label (sin opciones configuradas)',
            style: theme.textTheme.bodyMedium,
          ),
        );
      }
      final groupValue = _selectedOptions[pregunta.id];
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            for (final opcion in pregunta.opciones)
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                value: (opcion.valor != null && opcion.valor!.isNotEmpty)
                    ? opcion.valor!
                    : opcion.descripcion,
                groupValue: groupValue,
                title: Text(opcion.descripcion),
                onChanged: (value) {
                  setState(() {
                    _selectedOptions[pregunta.id] = value;
                    _prunePathAfterCurrent();
                  });
                },
              ),
          ],
        ),
      );
    }

    final controller = _controllers[pregunta.id];
    final keyboardType = tipo == 'N' ? TextInputType.number : TextInputType.text;
    final isDate = tipo == 'F';
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            readOnly: isDate,
            keyboardType: keyboardType,
            onTap: isDate ? () => _pickDate(pregunta) : null,
            decoration: InputDecoration(
              hintText: isDate ? 'YYYY-MM-DD' : null,
              suffixIcon: isDate ? const Icon(Icons.date_range) : null,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.visitLabel?.trim().isNotEmpty == true
        ? 'Cuestionario - ${widget.visitLabel}'
        : 'Cuestionario';
    final current = _currentQuestion;
    final hasNext = _hasNextQuestion;
    final buttonLabel = hasNext ? 'Siguiente' : 'Guardar';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.cuestionario.nombre,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (widget.cuestionario.descripcion?.trim().isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 12),
                  child: Text(widget.cuestionario.descripcion!),
                )
              else
                const SizedBox(height: 12),
              if (current == null)
                const Expanded(
                  child: Center(child: Text('No hay preguntas disponibles.')),
                )
              else ...[
                Expanded(
                  child: ListView(
                    children: [_buildPregunta(current)],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                        child: const Text('Cancelar'),
                      ),
                      if (_questionPath.length > 1)
                        TextButton(
                          onPressed: _saving ? null : _goToPreviousQuestion,
                          child: const Text('Anterior'),
                        ),
                      const Spacer(),
                      ElevatedButton.icon(
                        onPressed: _saving
                            ? null
                            : hasNext
                                ? (_canGoToNext ? _goToNextQuestion : null)
                                : _submit,
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.check),
                        label: Text(buttonLabel),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
