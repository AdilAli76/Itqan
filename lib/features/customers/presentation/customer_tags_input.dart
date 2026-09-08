import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// أداة إدخال أوسمِ العميل — تسمح بإضافة وحذف الأوسمِ بسهولة.
class CustomerTagsInput extends ConsumerStatefulWidget {
  final List<String> initialTags;
  final Function(List<String>) onChanged;
  final List<String> suggestedTags;

  const CustomerTagsInput({
    Key? key,
    this.initialTags = const [],
    required this.onChanged,
    this.suggestedTags = const [],
  }) : super(key: key);

  @override
  ConsumerState<CustomerTagsInput> createState() => _CustomerTagsInputState();
}

class _CustomerTagsInputState extends ConsumerState<CustomerTagsInput> {
  late List<String> _tags;
  late TextEditingController _controller;
  List<String> _filteredSuggestions = [];

  @override
  void initState() {
    super.initState();
    _tags = List.from(widget.initialTags);
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _addTag(String tag) {
    tag = tag.trim();
    if (tag.isEmpty || _tags.contains(tag)) return;

    setState(() {
      _tags.add(tag);
      _controller.clear();
      _filteredSuggestions.clear();
    });
    widget.onChanged(_tags);
  }

  void _removeTag(String tag) {
    setState(() {
      _tags.remove(tag);
    });
    widget.onChanged(_tags);
  }

  void _updateSuggestions(String value) {
    if (value.isEmpty) {
      setState(() => _filteredSuggestions.clear());
      return;
    }

    final filtered = widget.suggestedTags
        .where((tag) =>
            tag.contains(value) && !_tags.contains(tag))
        .toList();
    setState(() => _filteredSuggestions = filtered);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // الأوسمِ المضافة
        if (_tags.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _tags.map((tag) => Chip(
              label: Text(tag, style: const TextStyle(fontSize: 12)),
              onDeleted: () => _removeTag(tag),
              backgroundColor: Colors.blue.shade100,
              deleteIcon: const Icon(Icons.close, size: 16),
            )).toList(),
          ),
        const SizedBox(height: 12),
        // حقل الإدخال
        Autocomplete<String>(
          optionsBuilder: (TextEditingValue textEditingValue) {
            if (textEditingValue.text.isEmpty) return [];
            return widget.suggestedTags
                .where((tag) =>
                    tag.contains(textEditingValue.text) &&
                    !_tags.contains(tag))
                .toList();
          },
          onSelected: (String selection) {
            _addTag(selection);
          },
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            return TextField(
              controller: controller,
              focusNode: focusNode,
              decoration: InputDecoration(
                hintText: 'أضف وسمْاً (مثلاً: VIP، مشتر متكرر)',
                hintStyle: TextStyle(color: Colors.grey[400]),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                suffixIcon: controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () => _addTag(controller.text),
                      )
                    : null,
              ),
              onChanged: (value) {
                _controller.text = value;
                _updateSuggestions(value);
              },
              onSubmitted: (value) {
                if (value.isNotEmpty) {
                  _addTag(value);
                  controller.clear();
                }
              },
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            return Material(
              elevation: 4.0,
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options.elementAt(index);
                  return ListTile(
                    title: Text(option, style: const TextStyle(fontSize: 12)),
                    onTap: () => onSelected(option),
                    dense: true,
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }
}
