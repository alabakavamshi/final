import 'package:cloud_firestore/cloud_firestore.dart';

class Tournament {
  final String id;
  final String name;
  final String venue;
  final String city;
  final DateTime eventDate;
  final DateTime? endDate; // Added endDate field
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
    required this.eventDate,
    this.endDate, // Optional endDate
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
      'eventDate': eventDate,
      'endDate': endDate, // Add endDate to Firestore serialization
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
    return Tournament(
      id: id,
      name: data['name'] ?? '',
      venue: data['venue'] ?? '',
      city: data['city'] ?? '',
      eventDate: (data['eventDate'] as Timestamp).toDate(),
      endDate: data['endDate'] != null ? (data['endDate'] as Timestamp).toDate() : null, // Deserialize endDate
      entryFee: (data['entryFee'] as num).toDouble(),
      status: data['status'] ?? 'open',
      createdBy: data['createdBy'] ?? '',
      createdAt: (data['createdAt'] as Timestamp).toDate(),
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