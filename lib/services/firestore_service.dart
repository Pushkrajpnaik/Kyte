import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/member.dart';
import '../utils/demo_member_seed.dart';

class MemberDataException implements Exception {
  const MemberDataException(this.message);

  final String message;

  @override
  String toString() => message;
}

class FirestoreService {
  FirestoreService({bool demoMode = false})
    : _demoMode = demoMode,
      _demoMembers = List<Member>.from(demoMembers),
      _demoController = StreamController<List<Member>>.broadcast() {
    if (!_demoMode) {
      _configureFirestore();
    }
  }

  final bool _demoMode;
  bool _localFallback = false;
  final List<Member> _demoMembers;
  final StreamController<List<Member>> _demoController;
  FirebaseFirestore? _firestore;

  FirebaseFirestore get _firestoreClient {
    return _firestore ??= FirebaseFirestore.instance;
  }

  bool get isDemoMode => _demoMode || _localFallback;

  bool get isLocalFallback => _localFallback;

  bool get _isLocalMode => _demoMode || _localFallback;

  Future<void> enableLocalFallback() async {
    if (_localFallback) {
      return;
    }

    _localFallback = true;
    if (_demoMembers.isEmpty) {
      _demoMembers.addAll(demoMembers);
    }
    emitCurrentMembers();
  }

  void _configureFirestore() {
    try {
      _firestoreClient.settings = const Settings(persistenceEnabled: true);
    } catch (_) {
      // If settings are already applied, keep the existing instance configuration.
    }
  }

  Future<List<Member>> getMembersOnce() async {
    if (_isLocalMode) {
      return _sortedDemoMembers();
    }

    return _executeWithRetry(() async {
      final snapshot = await _firestoreClient.collection('members').get();
      final members = snapshot.docs.map(Member.fromFirestore).toList();
      members.sort((left, right) => left.name.compareTo(right.name));
      return members;
    }, defaultMessage: 'Unable to load members right now.');
  }

  Future<Member?> getMemberById(String memberId) async {
    if (memberId.isEmpty) {
      return null;
    }

    if (_isLocalMode) {
      for (final member in _demoMembers) {
        if (member.id == memberId) {
          return member;
        }
      }
      return null;
    }

    return _executeWithRetry(() async {
      final doc = await _firestoreClient
          .collection('members')
          .doc(memberId)
          .get();
      if (!doc.exists) {
        return null;
      }
      return Member.fromFirestore(doc);
    }, defaultMessage: 'Unable to load this member right now.');
  }

  Future<bool> isCircular(String memberId, String? newManagerId) async {
    if (newManagerId == null || newManagerId.isEmpty) {
      return false;
    }

    if (memberId == newManagerId) {
      return true;
    }

    var currentManagerId = newManagerId;
    final visited = <String>{};

    while (currentManagerId.isNotEmpty && visited.add(currentManagerId)) {
      if (currentManagerId == memberId) {
        return true;
      }

      final manager = await getMemberById(currentManagerId);
      if (manager == null) {
        return false;
      }

      currentManagerId = manager.managerId ?? '';
    }

    return false;
  }

  Stream<List<Member>> watchMembers() {
    if (_isLocalMode) {
      return _demoController.stream;
    }

    return _firestoreClient.collection('members').snapshots().map((snapshot) {
      final members = snapshot.docs.map(Member.fromFirestore).toList();
      members.sort((left, right) => left.name.compareTo(right.name));
      return members;
    });
  }

  Future<void> ensureSeedDataIfEmpty() async {
    if (_isLocalMode) {
      return;
    }

    await _executeWithRetry(() async {
      final collection = _firestoreClient.collection('members');
      final existing = await collection.limit(1).get();
      if (existing.docs.isNotEmpty) {
        return;
      }

      final batch = _firestoreClient.batch();
      for (final member in demoMembers) {
        batch.set(collection.doc(member.id), member.toMap());
      }
      await batch.commit();
    }, defaultMessage: 'Unable to seed members right now.');
  }

  void emitCurrentMembers() {
    if (!_isLocalMode || _demoController.isClosed) {
      return;
    }

    _demoController.add(_sortedDemoMembers());
  }

  Future<String> addMember(Member member) async {
    if (_isLocalMode) {
      final newMember = member.id.isEmpty
          ? member.copyWith(id: 'demo-${DateTime.now().millisecondsSinceEpoch}')
          : member;
      _demoMembers.add(newMember);
      emitCurrentMembers();
      return newMember.id;
    }

    try {
      return await _executeWithRetry(() async {
        final docRef = member.id.isEmpty
            ? _firestoreClient.collection('members').doc()
            : _firestoreClient.collection('members').doc(member.id);
        final payload = member.copyWith(id: docRef.id);
        await docRef.set(payload.toMap());
        return docRef.id;
      }, defaultMessage: 'Unable to add member right now.');
    } catch (error) {
      await enableLocalFallback();
      return addMember(member);
    }
  }

  Future<void> updateMember(Member member) async {
    if (_isLocalMode) {
      final index = _demoMembers.indexWhere((item) => item.id == member.id);
      if (index != -1) {
        _demoMembers[index] = member;
        emitCurrentMembers();
      }
      return;
    }

    try {
      await _executeWithRetry(() async {
        await _firestoreClient
            .collection('members')
            .doc(member.id)
            .set(member.toMap());
      }, defaultMessage: 'Unable to update member right now.');
    } catch (error) {
      await enableLocalFallback();
      await updateMember(member);
    }
  }

  Future<void> deleteMember(String memberId) async {
    if (_isLocalMode) {
      _demoMembers.removeWhere((member) => member.id == memberId);
      emitCurrentMembers();
      return;
    }

    try {
      await _executeWithRetry(() async {
        await _firestoreClient.collection('members').doc(memberId).delete();
      }, defaultMessage: 'Unable to delete member right now.');
    } catch (error) {
      await enableLocalFallback();
      await deleteMember(memberId);
    }
  }

  Future<void> deleteSubtree(String memberId) async {
    final members = await getMembersOnce();
    final idsToDelete = _collectSubtreeIds(memberId, members);

    if (_isLocalMode) {
      _demoMembers.removeWhere((member) => idsToDelete.contains(member.id));
      emitCurrentMembers();
      return;
    }

    const batchLimit = 500;
    var index = 0;
    while (index < idsToDelete.length) {
      final chunkEnd = (index + batchLimit).clamp(0, idsToDelete.length);
      await _executeWithRetry(() async {
        final batch = _firestoreClient.batch();
        for (final id in idsToDelete.sublist(index, chunkEnd)) {
          batch.delete(_firestoreClient.collection('members').doc(id));
        }
        await batch.commit();
      }, defaultMessage: 'Unable to delete this subtree right now.');
      index = chunkEnd;
    }
  }

  bool _isTransientError(Object error) {
    if (error is! FirebaseException) {
      return false;
    }

    return error.code == 'unavailable' ||
        error.code == 'deadline-exceeded' ||
        error.code == 'aborted';
  }

  Future<T> _executeWithRetry<T>(
    Future<T> Function() operation, {
    required String defaultMessage,
    int maxAttempts = 3,
  }) async {
    var attempt = 0;
    while (true) {
      attempt++;
      try {
        return await operation();
      } catch (error) {
        final shouldRetry = attempt < maxAttempts && _isTransientError(error);
        if (shouldRetry) {
          final delayMs = 300 * (1 << (attempt - 1));
          await Future<void>.delayed(Duration(milliseconds: delayMs));
          continue;
        }

        throw MemberDataException(
          _friendlyErrorMessage(error, defaultMessage: defaultMessage),
        );
      }
    }
  }

  String _friendlyErrorMessage(Object error, {required String defaultMessage}) {
    if (error is FirebaseException) {
      if (error.code == 'permission-denied') {
        return 'Access denied. Please check Firestore rules.';
      }

      if (error.code == 'unavailable') {
        return 'Service unavailable. Please try again.';
      }

      if (error.code == 'deadline-exceeded') {
        return 'Request timed out. Please try again.';
      }
    }

    if (error is MemberDataException) {
      return error.message;
    }

    return defaultMessage;
  }

  List<String> _collectSubtreeIds(String rootMemberId, List<Member> members) {
    final childLookup = <String, List<String>>{};
    for (final member in members) {
      final managerId = member.managerId;
      if (managerId == null || managerId.isEmpty) {
        continue;
      }

      childLookup.putIfAbsent(managerId, () => <String>[]).add(member.id);
    }

    final idsToDelete = <String>[];
    final queue = <String>[rootMemberId];

    while (queue.isNotEmpty) {
      final currentId = queue.removeAt(0);
      idsToDelete.add(currentId);
      queue.addAll(childLookup[currentId] ?? const <String>[]);
    }

    return idsToDelete;
  }

  List<Member> _sortedDemoMembers() {
    final members = List<Member>.from(_demoMembers);
    members.sort((left, right) => left.name.compareTo(right.name));
    return members;
  }

  void dispose() {
    _demoController.close();
  }
}
