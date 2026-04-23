import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../providers/member_provider.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String? _roleFilter;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Users')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Consumer<MemberProvider>(
            builder: (context, provider, _) {
              if (provider.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              final errorMessage = provider.errorMessage;
              final filteredMembers = _filterMembers(provider.members);
              final roles =
                  provider.members.map((member) => member.role).toSet().toList()
                    ..sort();

              return Column(
                children: [
                  _buildSearchAndFilter(roles),
                  if (errorMessage != null) ...[
                    const SizedBox(height: 10),
                    _ErrorBanner(message: errorMessage),
                  ],
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Users (${filteredMembers.length})'),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filteredMembers.isEmpty
                        ? const Center(
                            child: Text('No users match your filters.'),
                          )
                        : ListView.separated(
                            itemBuilder: (context, index) {
                              final member = filteredMembers[index];
                              return _UserCard(member: member);
                            },
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemCount: filteredMembers.length,
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSearchAndFilter(List<String> roles) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchController,
            onChanged: (value) {
              setState(() {
                _query = value;
              });
            },
            decoration: InputDecoration(
              hintText: 'Search users',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        setState(() {
                          _query = '';
                          _searchController.clear();
                        });
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        PopupMenuButton<String?>(
          tooltip: 'Filter users',
          initialValue: _roleFilter,
          onSelected: (value) {
            setState(() {
              _roleFilter = value;
            });
          },
          itemBuilder: (context) {
            return [
              const PopupMenuItem<String?>(
                value: null,
                child: Text('All roles'),
              ),
              ...roles.map(
                (role) =>
                    PopupMenuItem<String?>(value: role, child: Text(role)),
              ),
            ];
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white24),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.filter_list_rounded, size: 18),
                const SizedBox(width: 6),
                Text(_roleFilter ?? 'Filter'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Member> _filterMembers(List<Member> members) {
    final normalizedQuery = _query.trim().toLowerCase();

    return members
        .where((member) {
          final roleMatches = _roleFilter == null || member.role == _roleFilter;
          if (!roleMatches) {
            return false;
          }

          if (normalizedQuery.isEmpty) {
            return true;
          }

          return member.name.toLowerCase().contains(normalizedQuery) ||
              member.role.toLowerCase().contains(normalizedQuery) ||
              member.department.toLowerCase().contains(normalizedQuery) ||
              member.team.toLowerCase().contains(normalizedQuery);
        })
        .toList(growable: false);
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({required this.member});

  final Member member;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Text(_initials(member.name))),
        title: Text(member.name),
        subtitle: Text('${member.role}\n${member.department} • ${member.team}'),
        isThreeLine: true,
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) {
      return '?';
    }
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: 0.28)),
      ),
      child: Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: Colors.red.shade200),
      ),
    );
  }
}
