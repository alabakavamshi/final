import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class Tournament {
  final String id;
  final String name;
  final String venue;
  final String city;
  final DateTime startDate;
  final TimeOfDay startTime;
  final DateTime? endDate;
  final double entryFee;
  final String status;
  final String createdBy;
  final DateTime createdAt;
  final List<Map<String, dynamic>> participants;
  final String rules;
  final int maxParticipants;
  final String gameFormat;
  final String gameType;
  final bool bringOwnEquipment;
  final bool costShared;
  final List<Map<String, dynamic>> matches;
  final List<Map<String, dynamic>> teams;

  Tournament({
    required this.id,
    required this.name,
    required this.venue,
    required this.city,
    required this.startDate,
    required this.startTime,
    this.endDate,
    required this.entryFee,
    required this.status,
    required this.createdBy,
    required this.createdAt,
    required this.participants,
    required this.rules,
    required this.maxParticipants,
    required this.gameFormat,
    required this.gameType,
    required this.bringOwnEquipment,
    required this.costShared,
    this.matches = const [],
    this.teams = const [],
  });

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'name': name,
      'venue': venue,
      'city': city,
      'startDate': Timestamp.fromDate(startDate), // Store as separate Timestamp
      'startTime': {
        'hour': startTime.hour,
        'minute': startTime.minute,
      }, // Store as a map for TimeOfDay
      'endDate': endDate != null ? Timestamp.fromDate(endDate!) : null,
      'entryFee': entryFee,
      'status': status,
      'createdBy': createdBy,
      'createdAt': createdAt,
      'participants': participants,
      'rules': rules,
      'maxParticipants': maxParticipants,
      'gameFormat': gameFormat,
      'gameType': gameType,
      'bringOwnEquipment': bringOwnEquipment,
      'costShared': costShared,
      'matches': matches,
      'teams': teams,
    };
  }

  factory Tournament.fromFirestore(Map<String, dynamic> data, String id) {
    // Handle null startDate by providing a default (current date)
    final startDate =
        (data['startDate'] as Timestamp?)?.toDate() ?? DateTime.now();

    // Handle null startTime with default values
    final startTimeData =
        data['startTime'] as Map<String, dynamic>? ?? {'hour': 0, 'minute': 0};

    return Tournament(
      id: id,
      name: data['name'] ?? '',
      venue: data['venue'] ?? '',
      city: data['city'] ?? '',
      startDate: startDate,
      startTime: TimeOfDay(
        hour: startTimeData['hour'] as int,
        minute: startTimeData['minute'] as int,
      ),
      endDate:
          data['endDate'] != null
              ? (data['endDate'] as Timestamp).toDate()
              : null,
      entryFee: (data['entryFee'] as num?)?.toDouble() ?? 0.0,
      status: data['status'] ?? 'open',
      createdBy: data['createdBy'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      participants: List<Map<String, dynamic>>.from(data['participants'] ?? []),
      rules: data['rules'] ?? '',
      maxParticipants: data['maxParticipants'] ?? 0,
      gameFormat: data['gameFormat'] ?? 'Singles',
      gameType: data['gameType'] ?? 'Tournament',
      bringOwnEquipment: data['bringOwnEquipment'] ?? false,
      costShared: data['costShared'] ?? false,
      matches: List<Map<String, dynamic>>.from(data['matches'] ?? []),
      teams: List<Map<String, dynamic>>.from(data['teams'] ?? []),
    );
  }
}
