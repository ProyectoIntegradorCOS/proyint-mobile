import 'package:flutter/material.dart';

import '../../models/assigned_visit.dart';

class VerificationFormScreen extends StatefulWidget {
  final AssignedVisit visit;

  const VerificationFormScreen({super.key, required this.visit});

  @override
  State<VerificationFormScreen> createState() => _VerificationFormScreenState();
}

class _VerificationFormScreenState extends State<VerificationFormScreen> {
  late final int total;
  int index = 0;
  final _nameController = TextEditingController();
  final _idController = TextEditingController();
  final _notesController = TextEditingController();
  final List<Map<String, String>> entries = [];

  @override
  void initState() {
    super.initState();
    total = widget.visit.peopleToVerify > 0 ? widget.visit.peopleToVerify : 1;
    entries.addAll(List.generate(total, (_) => <String, String>{}));
    _loadFromEntry();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _idController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _loadFromEntry() {
    final e = entries[index];
    _nameController.text = e['name'] ?? '';
    _idController.text = e['doc'] ?? '';
    _notesController.text = e['notes'] ?? '';
  }

  void _saveCurrent() {
    entries[index] = {
      'name': _nameController.text.trim(),
      'doc': _idController.text.trim(),
      'notes': _notesController.text.trim(),
    };
  }

  bool _isEntryValid(Map<String, String> e) {
    return (e['name']?.isNotEmpty ?? false) && (e['doc']?.isNotEmpty ?? false);
  }

  Future<void> _next() async {
    _saveCurrent();
    if (index < total - 1) {
      setState(() {
        index++;
      });
      _loadFromEntry();
    }
  }

  Future<void> _prev() async {
    _saveCurrent();
    if (index > 0) {
      setState(() {
        index--;
      });
      _loadFromEntry();
    }
  }

  Future<void> _finalize() async {
    _saveCurrent();
    // Validate all
    final invalidAt = entries.indexWhere((e) => !_isEntryValid(e));
    if (invalidAt != -1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falta completar datos en persona ${invalidAt + 1}')),
      );
      setState(() => index = invalidAt);
      _loadFromEntry();
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Verificación - ${widget.visit.name}'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Persona ${index + 1} de $total', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nombre completo',
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _idController,
                decoration: const InputDecoration(
                  labelText: 'Documento de identidad',
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Observaciones',
                ),
                maxLines: 3,
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  OutlinedButton(
                    onPressed: index > 0 ? _prev : null,
                    child: const Text('Anterior'),
                  ),
                  if (index < total - 1)
                    ElevatedButton(
                      onPressed: _next,
                      child: const Text('Siguiente'),
                    )
                  else
                    ElevatedButton.icon(
                      onPressed: _finalize,
                      icon: const Icon(Icons.check),
                      label: const Text('Se culminó la verificación'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

