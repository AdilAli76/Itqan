import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// اختيار فئة العميل من قائمة منسدلة.
class CustomerCategorySelector extends ConsumerWidget {
  final Guid? selectedCategoryId;
  final Function(Guid?) onChanged;
  final bool isRequired;

  const CustomerCategorySelector({
    Key? key,
    required this.selectedCategoryId,
    required this.onChanged,
    this.isRequired = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // افترض أن هناك provider يجلب الفئات
    // final categoriesAsync = ref.watch(customerCategoriesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'فئة العميل',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        // سيتم استبدال هذا بـ categoriesAsync.when() عند التكامل
        DropdownButton<Guid?>(
          value: selectedCategoryId,
          isExpanded: true,
          hint: const Text('اختر فئة'),
          items: [] /* سيتم ملؤها من provider */,
          onChanged: onChanged,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ],
    );
  }
}

// نسخة بسيطة للاختبار السريع
class SimpleCustomerCategoryDropdown extends StatelessWidget {
  final Guid? selectedId;
  final Function(Guid?) onChanged;
  final List<({Guid id, String name})> categories;

  const SimpleCustomerCategoryDropdown({
    Key? key,
    required this.selectedId,
    required this.onChanged,
    required this.categories,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<Guid?>(
      value: selectedId,
      decoration: InputDecoration(
        labelText: 'فئة العميل',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      items: [
        const DropdownMenuItem<Guid?>(
          value: null,
          child: Text('بدون فئة'),
        ),
        ...categories.map((cat) =>
            DropdownMenuItem<Guid?>(
              value: cat.id,
              child: Text(cat.name),
            )),
      ],
      onChanged: onChanged,
    );
  }
}

// كود مساعد لتعريف Guid (يجب أن يكون موجوداً بالفعل)
typedef Guid = String;
