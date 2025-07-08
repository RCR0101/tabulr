// import 'package:flutter/material.dart';
// import '../models/course.dart';

// class AddCourseDialog extends StatefulWidget {
//   final Function(Course) onCourseAdded;

//   const AddCourseDialog({
//     super.key,
//     required this.onCourseAdded,
//   });

//   @override
//   State<AddCourseDialog> createState() => _AddCourseDialogState();
// }

// class _AddCourseDialogState extends State<AddCourseDialog> {
//   final _formKey = GlobalKey<FormState>();
//   final _courseCodeController = TextEditingController();
//   final _courseTitleController = TextEditingController();
//   final _lectureCreditsController = TextEditingController();
//   final _practicalCreditsController = TextEditingController();
//   final _totalCreditsController = TextEditingController();

//   final List<SectionFormData> _sections = [];

//   @override
//   void initState() {
//     super.initState();
//     _addSection();
//   }

//   void _addSection() {
//     setState(() {
//       _sections.add(SectionFormData());
//     });
//   }

//   void _removeSection(int index) {
//     setState(() {
//       _sections.removeAt(index);
//     });
//   }

//   void _submitForm() {
//     if (_formKey.currentState!.validate()) {
//       final course = Course(
//         courseCode: _courseCodeController.text,
//         courseTitle: _courseTitleController.text,
//         lectureCredits: int.parse(_lectureCreditsController.text),
//         practicalCredits: int.parse(_practicalCreditsController.text),
//         totalCredits: int.parse(_totalCreditsController.text),
//         sections: _sections.map((s) => s.toSection()).toList(),
//       );

//       widget.onCourseAdded(course);
//       Navigator.pop(context);
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Dialog(
//       child: Container(
//         width: 600,
//         height: 500,
//         padding: const EdgeInsets.all(16),
//         child: Form(
//           key: _formKey,
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               const Text(
//                 'Add New Course',
//                 style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
//               ),
//               const SizedBox(height: 16),
//               Row(
//                 children: [
//                   Expanded(
//                     child: TextFormField(
//                       controller: _courseCodeController,
//                       decoration: const InputDecoration(labelText: 'Course Code'),
//                       validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
//                     ),
//                   ),
//                   const SizedBox(width: 16),
//                   Expanded(
//                     flex: 2,
//                     child: TextFormField(
//                       controller: _courseTitleController,
//                       decoration: const InputDecoration(labelText: 'Course Title'),
//                       validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
//                     ),
//                   ),
//                 ],
//               ),
//               const SizedBox(height: 16),
//               Row(
//                 children: [
//                   Expanded(
//                     child: TextFormField(
//                       controller: _lectureCreditsController,
//                       decoration: const InputDecoration(labelText: 'Lecture Credits'),
//                       keyboardType: TextInputType.number,
//                       validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
//                     ),
//                   ),
//                   const SizedBox(width: 16),
//                   Expanded(
//                     child: TextFormField(
//                       controller: _practicalCreditsController,
//                       decoration: const InputDecoration(labelText: 'Practical Credits'),
//                       keyboardType: TextInputType.number,
//                       validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
//                     ),
//                   ),
//                   const SizedBox(width: 16),
//                   Expanded(
//                     child: TextFormField(
//                       controller: _totalCreditsController,
//                       decoration: const InputDecoration(labelText: 'Total Credits'),
//                       keyboardType: TextInputType.number,
//                       validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
//                     ),
//                   ),
//                 ],
//               ),
//               const SizedBox(height: 16),
//               const Text(
//                 'Sections',
//                 style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
//               ),
//               Expanded(
//                 child: ListView.builder(
//                   itemCount: _sections.length,
//                   itemBuilder: (context, index) {
//                     return SectionFormWidget(
//                       sectionData: _sections[index],
//                       onRemove: () => _removeSection(index),
//                     );
//                   },
//                 ),
//               ),
//               Row(
//                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                 children: [
//                   TextButton(
//                     onPressed: _addSection,
//                     child: const Text('Add Section'),
//                   ),
//                   Row(
//                     children: [
//                       TextButton(
//                         onPressed: () => Navigator.pop(context),
//                         child: const Text('Cancel'),
//                       ),
//                       const SizedBox(width: 8),
//                       ElevatedButton(
//                         onPressed: _submitForm,
//                         child: const Text('Add Course'),
//                       ),
//                     ],
//                   ),
//                 ],
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }

// class SectionFormData {
//   final TextEditingController sectionIdController = TextEditingController();
//   final TextEditingController instructorController = TextEditingController();
//   final TextEditingController roomController = TextEditingController();
//   final TextEditingController hoursController = TextEditingController();
//   SectionType selectedType = SectionType.L;
//   List<DayOfWeek> selectedDays = [];

//   Section toSection() {
//     return Section(
//       sectionId: sectionIdController.text,
//       type: selectedType,
//       instructor: instructorController.text,
//       room: roomController.text,
//       days: selectedDays,
//       hours: hoursController.text
//           .split(',')
//           .map((h) => int.parse(h.trim()))
//           .toList(),
//     );
//   }
// }

// class SectionFormWidget extends StatefulWidget {
//   final SectionFormData sectionData;
//   final VoidCallback onRemove;

//   const SectionFormWidget({
//     super.key,
//     required this.sectionData,
//     required this.onRemove,
//   });

//   @override
//   State<SectionFormWidget> createState() => _SectionFormWidgetState();
// }

// class _SectionFormWidgetState extends State<SectionFormWidget> {
//   @override
//   Widget build(BuildContext context) {
//     return Card(
//       margin: const EdgeInsets.symmetric(vertical: 4),
//       child: Padding(
//         padding: const EdgeInsets.all(8),
//         child: Column(
//           children: [
//             Row(
//               children: [
//                 Expanded(
//                   child: TextFormField(
//                     controller: widget.sectionData.sectionIdController,
//                     decoration: const InputDecoration(labelText: 'Section ID'),
//                     validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
//                   ),
//                 ),
//                 const SizedBox(width: 8),
//                 DropdownButton<SectionType>(
//                   value: widget.sectionData.selectedType,
//                   onChanged: (value) {
//                     setState(() {
//                       widget.sectionData.selectedType = value!;
//                     });
//                   },
//                   items: SectionType.values.map((type) {
//                     return DropdownMenuItem(
//                       value: type,
//                       child: Text(type.name),
//                     );
//                   }).toList(),
//                 ),
//                 IconButton(
//                   icon: const Icon(Icons.delete),
//                   onPressed: widget.onRemove,
//                 ),
//               ],
//             ),
//             Row(
//               children: [
//                 Expanded(
//                   child: TextFormField(
//                     controller: widget.sectionData.instructorController,
//                     decoration: const InputDecoration(labelText: 'Instructor'),
//                   ),
//                 ),
//                 const SizedBox(width: 8),
//                 Expanded(
//                   child: TextFormField(
//                     controller: widget.sectionData.roomController,
//                     decoration: const InputDecoration(labelText: 'Room'),
//                   ),
//                 ),
//               ],
//             ),
//             TextFormField(
//               controller: widget.sectionData.hoursController,
//               decoration: const InputDecoration(
//                 labelText: 'Hours (comma separated)',
//                 hintText: '1,2,3',
//               ),
//             ),
//             Wrap(
//               children: DayOfWeek.values.map((day) {
//                 return FilterChip(
//                   label: Text(day.name),
//                   selected: widget.sectionData.selectedDays.contains(day),
//                   onSelected: (selected) {
//                     setState(() {
//                       if (selected) {
//                         widget.sectionData.selectedDays.add(day);
//                       } else {
//                         widget.sectionData.selectedDays.remove(day);
//                       }
//                     });
//                   },
//                 );
//               }).toList(),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }