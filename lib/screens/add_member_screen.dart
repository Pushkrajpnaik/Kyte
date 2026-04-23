import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../providers/member_provider.dart';
import '../utils/app_theme.dart';
import '../utils/member_roles.dart';

class AddMemberScreen extends StatefulWidget {
  const AddMemberScreen({super.key, this.member, this.showHeader = true});

  final Member? member;
  final bool showHeader;

  @override
  State<AddMemberScreen> createState() => _AddMemberScreenState();
}

class _AddMemberScreenState extends State<AddMemberScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _departmentController = TextEditingController();
  final TextEditingController _teamController = TextEditingController();
  final TextEditingController _photoUrlController = TextEditingController();

  String? _selectedRole;
  String? _selectedManagerId;
  bool _isSaving = false;

  bool get _isEditMode => widget.member != null;

  @override
  void initState() {
    super.initState();
    final member = widget.member;
    if (member != null) {
      _nameController.text = member.name;
      _departmentController.text = member.department;
      _teamController.text = member.team;
      _photoUrlController.text = member.photoUrl ?? '';
      _selectedRole = member.role;
      _selectedManagerId = member.managerId;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _departmentController.dispose();
    _teamController.dispose();
    _photoUrlController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSaving) {
      return;
    }

    final formState = _formKey.currentState;
    if (formState == null || !formState.validate()) {
      return;
    }

    final provider = context.read<MemberProvider>();
    final memberId = widget.member?.id ?? '';

    if (await provider.isCircular(memberId, _selectedManagerId)) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Circular manager assignment is not allowed'),
        ),
      );
      return;
    }

    final newMember = Member(
      id: memberId,
      name: _nameController.text.trim(),
      role: _selectedRole!.trim(),
      department: _departmentController.text.trim(),
      team: _teamController.text.trim(),
      managerId: _selectedManagerId,
      photoUrl: _photoUrlController.text.trim().isEmpty
          ? null
          : _photoUrlController.text.trim(),
    );

    setState(() {
      _isSaving = true;
    });

    try {
      if (_isEditMode) {
        await provider.updateMember(newMember);
      } else {
        await provider.addMember(newMember);
      }
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isEditMode
                ? 'Member updated successfully'
                : 'Member added successfully',
          ),
        ),
      );
      if (widget.showHeader && Navigator.of(context).canPop()) {
        Navigator.of(context).pop(true);
      } else if (!_isEditMode) {
        _formKey.currentState?.reset();
        _nameController.clear();
        _departmentController.clear();
        _teamController.clear();
        _photoUrlController.clear();
        setState(() {
          _selectedRole = null;
          _selectedManagerId = null;
        });
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to add member: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final members = context.watch<MemberProvider>().members;
    final member = widget.member;
    final managerOptions = _managerOptions(members, member);

    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              if (widget.showHeader)
                _Header(onBack: () => Navigator.of(context).pop()),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionCard(
                        title: 'Member details',
                        subtitle: _isEditMode
                            ? 'Update the selected member and keep the hierarchy valid.'
                            : 'Create a new member record with the reporting relationship you need.',
                        child: Column(
                          children: [
                            _StyledField(
                              label: 'Name',
                              controller: _nameController,
                              hintText: 'Priya Sharma',
                              icon: Icons.person_outline_rounded,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Name is required';
                                }
                                return null;
                              },
                            ),
                            _StyledDropdown(
                              label: 'Role',
                              icon: Icons.work_outline_rounded,
                              value: _selectedRole,
                              hintText: 'Select a role',
                              items: memberRoles,
                              onChanged: (value) {
                                setState(() {
                                  _selectedRole = value;
                                });
                              },
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Role is required';
                                }
                                return null;
                              },
                            ),
                            _StyledField(
                              label: 'Department',
                              controller: _departmentController,
                              hintText: 'Engineering',
                              icon: Icons.apartment_rounded,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Department is required';
                                }
                                return null;
                              },
                            ),
                            _StyledField(
                              label: 'Team',
                              controller: _teamController,
                              hintText: 'Platform',
                              icon: Icons.groups_rounded,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Team is required';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _SectionCard(
                        title: 'Reporting line',
                        subtitle:
                            'Pick an existing member as manager, or keep this member at the root level.',
                        child: _StyledDropdown<String?>(
                          label: 'Manager',
                          icon: Icons.account_tree_outlined,
                          value: _selectedManagerId,
                          hintText: 'No manager (root node)',
                          items: managerOptions,
                          itemBuilder: (value) {
                            if (value == null) {
                              return 'No manager (root node)';
                            }

                            final manager = members.firstWhere(
                              (member) => member.id == value,
                              orElse: () => const Member(
                                id: '',
                                name: 'Unknown manager',
                                role: '',
                                department: '',
                                team: '',
                              ),
                            );
                            return manager.name;
                          },
                          onChanged: (value) {
                            setState(() {
                              _selectedManagerId = value;
                            });
                          },
                          validator: (_) => null,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _SectionCard(
                        title: 'Profile media',
                        subtitle:
                            'Optional for sprint 2. If no photo URL is supplied, Kyte will render the initials avatar.',
                        child: _StyledField(
                          label: 'Photo URL (optional)',
                          controller: _photoUrlController,
                          hintText: 'https://...',
                          icon: Icons.image_outlined,
                          validator: (_) => null,
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _isSaving ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accentBlue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: _isSaving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  _isEditMode ? 'Save Changes' : 'Add Member',
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<String?> _managerOptions(List<Member> members, Member? currentMember) {
    final options = <String?>[null];
    for (final member in members) {
      if (currentMember != null && member.id == currentMember.id) {
        continue;
      }
      options.add(member.id);
    }

    final currentManagerId = currentMember?.managerId;
    if (currentManagerId != null &&
        currentManagerId.isNotEmpty &&
        !options.contains(currentManagerId)) {
      options.add(currentManagerId);
    }

    return options;
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            AppTheme.accentBlue.withValues(alpha: 0.2),
            AppTheme.bgDeep,
          ],
        ),
        border: const Border(
          bottom: BorderSide(color: Color(0xFF1E293B), width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onBack,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF1E293B)),
              ),
              child: const Icon(
                Icons.arrow_back_rounded,
                color: AppTheme.textSecondary,
                size: 18,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Add Member', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(
            'Create a new profile and connect it to the org chart.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _StyledField extends StatelessWidget {
  const _StyledField({
    required this.label,
    required this.controller,
    required this.hintText,
    required this.icon,
    required this.validator,
  });

  final String label;
  final TextEditingController controller;
  final String hintText;
  final IconData icon;
  final String? Function(String?) validator;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        validator: validator,
        style: const TextStyle(color: AppTheme.textPrimary),
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          prefixIcon: Icon(icon, size: 18, color: AppTheme.textMuted),
          filled: true,
          fillColor: AppTheme.bgElevated,
          labelStyle: const TextStyle(color: AppTheme.textSecondary),
          hintStyle: const TextStyle(color: AppTheme.textMuted),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF1E293B)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(
              color: AppTheme.accentBlue,
              width: 1.5,
            ),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Colors.redAccent),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
          ),
        ),
      ),
    );
  }
}

class _StyledDropdown<T> extends StatelessWidget {
  const _StyledDropdown({
    required this.label,
    required this.icon,
    required this.value,
    required this.items,
    required this.hintText,
    required this.onChanged,
    required this.validator,
    this.itemBuilder,
  });

  final String label;
  final IconData icon;
  final T? value;
  final List<T> items;
  final String hintText;
  final ValueChanged<T?> onChanged;
  final String? Function(T?) validator;
  final String Function(T value)? itemBuilder;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<T>(
        value: value,
        isExpanded: true,
        menuMaxHeight: 320,
        validator: validator,
        dropdownColor: AppTheme.bgElevated,
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          prefixIcon: Icon(icon, size: 18, color: AppTheme.textMuted),
          filled: true,
          fillColor: AppTheme.bgElevated,
          labelStyle: const TextStyle(color: AppTheme.textSecondary),
          hintStyle: const TextStyle(color: AppTheme.textMuted),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF1E293B)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(
              color: AppTheme.accentBlue,
              width: 1.5,
            ),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Colors.redAccent),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
          ),
        ),
        items: items
            .map(
              (item) => DropdownMenuItem<T>(
                value: item,
                child: Text(
                  itemBuilder == null ? item.toString() : itemBuilder!(item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.textPrimary),
                ),
              ),
            )
            .toList(),
        onChanged: onChanged,
      ),
    );
  }
}
