import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/member.dart';
import '../services/firestore_service.dart';

class MemberProvider extends ChangeNotifier {
  MemberProvider(this._service) {
    unawaited(_connect());
  }

  final FirestoreService _service;
  StreamSubscription<List<Member>>? _subscription;

  List<Member> _members = <Member>[];
  bool _isLoading = true;
  String? _errorMessage;

  List<Member> get members => List.unmodifiable(_members);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isDemoMode => _service.isDemoMode;

  Future<void> _connect() async {
    if (!_service.isDemoMode) {
      try {
        await _service.ensureSeedDataIfEmpty();
      } catch (error) {
        _errorMessage = error.toString();
      }
    }

    await _attachMemberStream();

    if (_service.isDemoMode) {
      _service.emitCurrentMembers();
    }
  }

  Future<void> _attachMemberStream() async {
    await _subscription?.cancel();

    _subscription = _service.watchMembers().listen(
      (members) {
        _members = List<Member>.from(members)
          ..sort((left, right) => left.name.compareTo(right.name));
        _isLoading = false;
        _errorMessage = null;
        notifyListeners();
      },
      onError: (Object error, StackTrace stackTrace) {
        unawaited(_recoverFromStreamError(error));
      },
    );
  }

  Future<void> _recoverFromStreamError(Object error) async {
    if (!_shouldFallbackToLocal(error)) {
      _isLoading = false;
      _errorMessage = error.toString();
      notifyListeners();
      return;
    }

    await _service.enableLocalFallback();
    _errorMessage = null;
    await _attachMemberStream();
    _service.emitCurrentMembers();
  }

  Future<void> addMember(Member member) async {
    await _runAction(() => _service.addMember(member));
  }

  Future<void> updateMember(Member member) async {
    await _runAction(() => _service.updateMember(member));
  }

  Future<void> deleteMember(String memberId) async {
    await _runAction(() => _service.deleteMember(memberId));
  }

  Future<void> deleteSubtree(String memberId) async {
    await _runAction(() => _service.deleteSubtree(memberId));
  }

  Future<bool> isCircular(String memberId, String? newManagerId) =>
      _service.isCircular(memberId, newManagerId);

  Future<List<Member>> getMembersOnce() => _service.getMembersOnce();

  bool _shouldFallbackToLocal(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('unavailable') ||
        message.contains('deadline-exceeded') ||
        message.contains('channel shutdown') ||
        message.contains("backend didn't respond");
  }

  Future<T> _runAction<T>(Future<T> Function() action) async {
    try {
      final result = await action();
      _errorMessage = null;
      notifyListeners();
      return result;
    } catch (error) {
      _errorMessage = error.toString();
      notifyListeners();
      rethrow;
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _service.dispose();
    super.dispose();
  }
}
