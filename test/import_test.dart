import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymer/logic/legacy_import.dart';
import 'package:gymer/store.dart';

/// A trimmed export in the Flet app's "gymer-backup" ZIP layout.
List<int> fletBackup() {
  final files = {
    'manifest.json': jsonEncode({'format': 'gymer-backup', 'version': 1, 'files': {}}),
    'workouts.csv': 'workout_id,name\nA,Legs\n',
    'workout_exercises.csv':
        'workout_id,order_index,exercise_name,target_sets,default_weight,default_weight_unit,default_reps,rest_seconds,training_method\n'
        'A,1,Leg Press,2,,kg,,120,Straight\n'
        'A,2,Leg Curl,3,,kg,,90,Myo-Reps\n',
    'workout_set_templates.csv':
        'workout_id,order_index,set_number,set_type\nA,1,1,Warm-up\nA,1,2,Normal\nA,1,3,Top Set\n',
    'exercise_catalog.csv': 'exercise_name\nLeg Press\nLeg Curl\n',
    'exercise_details.csv':
        'exercise_name,primary_muscles,secondary_muscles,description,equipment_type,load_mode,straight_rep_min,straight_rep_max,straight_progression,weight_increment_kg\n'
        'Leg Press,Quads|Glutes,Hamstrings,"Feet high, ""slow"" lowering\nfull range",Plate loaded,external,6,10,double_progression,2.5\n',
    'sets.csv':
        'session_id,date,workout_id,workout_name,cycle_id,cycle_microcycle,cycle_phase,cycle_target_rir,exercise_name,set_number,weight,weight_unit,reps,rir,set_type,training_method,load_mode,note,completed,rest_seconds\n'
        's1,2026-09-02T18:00:00,A,Legs,c1,1,Build,3,Leg Press,1,100,kg,10,3,Normal,Straight,external,"good, deep",1,120\n'
        's1,2026-09-02T18:00:00,A,Legs,c1,1,Build,3,Leg Press,2,220.5,lb,9,2,Normal,Straight,external,,1,120\n'
        's1,2026-09-02T18:00:00,A,Legs,c1,1,Build,3,Leg Press,3,100,kg,9,2,Normal,Straight,external,,0,120\n',
    'mesocycles.csv':
        'cycle_id,name,start_date,microcycle_days,length_value,length_unit,deload_microcycles,start_rir,end_rir,deload_rir,deload_policy,deload_load_percent,deload_volume_percent,week_prescriptions,rir_lock,rest_timer_lock,setup_complete,active\n'
        'c1,Block 1,2026-09-01,7,6,weeks,1,3,1,4,recovery,90,50,"{""2"":{""rir"":""2""}}",1,0,1,1\n'
        'c0,Draft,2026-08-01,7,5,microcycles,1,3,1,4,recovery,90,50,{},1,0,0,0\n',
    'mesocycle_schedule.csv': 'cycle_id,day_number,workout_id\nc1,1,A\n',
    'cycle_day_events.csv':
        'cycle_id,planned_date,workout_id,workout_name,moved_to,status,session_id\nc1,2026-09-08,A,Legs,,missed,\n',
    'settings.csv': 'key,value\nunit,kg\nrounding,8\naccent_color,teal\nweight_increment_barbell_kg,2.5\n',
  };
  final archive = Archive();
  files.forEach((name, text) => archive.addFile(ArchiveFile.string(name, text)));
  return ZipEncoder().encodeBytes(archive);
}

void main() {
  test('imports a Flet backup ZIP faithfully', () async {
    final data = convertLegacy(readBackupZip(fletBackup()));
    final store = AppStore();
    await store.load();
    store.importLegacy(data);

    final legs = store.templates.single;
    expect(legs.exercises.first.types, ['Warm-up', 'Normal', 'Top Set']);
    expect(
      [legs.exercises.last.method, legs.exercises.last.types],
      [
        'Myo-Reps',
        ['Activation', 'Myo-set', 'Myo-set'],
      ],
    );

    final press = store.exercise('Leg Press')!;
    expect(
      [press.primary, press.repMin, press.repMax, press.incrementKg],
      [
        ['Quads', 'Glutes'],
        6,
        10,
        2.5,
      ],
    );
    expect(press.description, 'Feet high, "slow" lowering\nfull range');

    final s = store.history.single;
    expect((s.cycleId, s.microcycle, s.phase, s.targetRir), ('c1', 1, 'Build', 3));
    final logged = s.exercises.single.sets;
    expect(logged, hasLength(3), reason: 'unfinished planned rows stay in history');
    expect([for (final x in logged) x.done], [true, true, false]);
    expect(logged[1].weight, closeTo(100.017, 0.001), reason: 'lb rows convert to the session unit');
    expect(logged.first.note, 'good, deep');

    final c = store.cycles.single;
    expect(
      [c.length, c.weekRir, c.schedule, c.events['2026-09-08']!.status],
      [
        6,
        {2: 2},
        {1: 'A'},
        'missed',
      ],
    );
    // Modern keeps its own rounding; the backup's 8 is ignored.
    expect((store.settings.rounding, store.settings.accent, store.settings.increments['Barbell']!.$1), (18, 4, 2.5));
  });

  test('rejects ZIPs that are not Gymer backups', () {
    final archive = Archive()..addFile(ArchiveFile.string('notes.txt', 'hi'));
    expect(() => readBackupZip(ZipEncoder().encodeBytes(archive)), throwsFormatException);
  });
}
