"""Programmed segment variations are explicit, inherited or unknown without conversion."""
import copy
from types import SimpleNamespace
from test_data_integrity import TemporaryStorageTestCase
import storage
import set_context
import progression
from workouts import WorkoutMixin


class PlannedContextTests(TemporaryStorageTestCase):
    name='Mechanical variants'
    base={'setup':'Station A','side':'bilateral','load_convention':'total','rep_convention':'total'}

    def details(self, **changes):
        context={**self.base,**changes}
        storage.save_exercise_details(self.name,['Chest'],[],'','',logging_context=context)
        return context

    def plan(self, warmup=False):
        self.details()
        sets=[]
        if warmup: sets.append({'set_type':'Warm-up','weight':'20','reps':'5','rest_seconds':60})
        for index, variant in enumerate(['High handle','Middle handle','Low handle']*2):
            sets.append({'context_override':'1',**self.base,'setup':variant,'set_type':'Normal',
                         'weight':'50','reps':'12','rest_seconds':120 if index in (2,5) else 20,
                         'protocol_group_start':'1' if index==3 else ''})
        wid=storage.create_workout('Mechanical plan')
        storage.save_workout(wid,'Mechanical plan',[{'exercise_name':self.name,'training_method':'Mechanical Drop Set','sets':sets}])
        return wid

    def test_two_mechanical_groups_snapshot_variations_and_keep_same_loads(self):
        wid=self.plan()
        active=storage.build_active_workout(storage.read_workout(wid))
        self.assertEqual(['High handle','Middle handle','Low handle']*2,[r['setup'] for r in active['rows']])
        self.assertEqual(['50']*6,[r['previous_weight'] for r in active['rows']])
        self.assertEqual(2,len({r['group_id'] for r in active['rows']}))
        self.assertTrue(all(r['context_override']=='1' for r in active['rows']))
        self.assertEqual([20,20,120]*2,[r['rest_seconds'] for r in active['rows']])

    def test_default_changes_preserve_explicit_variants_and_clear_only_inherited_presets(self):
        wid=self.plan(warmup=True)
        active=storage.build_active_workout(storage.read_workout(wid))
        storage.save_active_workout(active)
        frozen=copy.deepcopy(storage.load_active_workout())
        self.details(setup='Station B',side='left')
        self.assertEqual(frozen,storage.load_active_workout())
        plan=storage.read_workout(wid)['exercises'][0]['sets']
        self.assertEqual(('', ''),(plan[0]['weight'],plan[0]['reps']))
        self.assertEqual(['50']*6,[r['weight'] for r in plan[1:]])
        new=storage.build_active_workout(storage.read_workout(wid))['rows']
        self.assertEqual('Station B',new[0]['setup'])
        self.assertEqual('left',new[0]['side'])
        self.assertEqual(['High handle','Middle handle','Low handle']*2,[r['setup'] for r in new[1:]])
        self.assertTrue(all(r['side']=='bilateral' for r in new[1:]))

    def test_first_explicit_variant_keeps_exercise_default_numbers(self):
        wid=self.plan()
        before=storage.read_workout(wid)['exercises'][0]['sets']
        self.details(setup='Station B')
        self.assertEqual(before,storage.read_workout(wid)['exercises'][0]['sets'])
        row=next(r for r in storage.read_exercises() if r['workout_id']==wid)
        self.assertEqual(('50','12'),(row['default_weight'],row['default_reps']))

    def test_explicit_unknown_does_not_inherit_and_legacy_rows_do(self):
        self.details()
        self.assertEqual(set_context.metadata(self.base),set_context.resolve({},self.base))
        self.assertEqual(set_context.metadata({}),set_context.resolve({'context_override':'1'},self.base))
        self.assertIsNone(set_context.template_key({'setup':'stale unused text'}))
        self.assertIsNotNone(set_context.template_key({'context_override':'1'}))
        self.assertEqual('',set_context.template_metadata({'context_override':'0'})['context_override'])

    def test_template_active_history_backup_and_unit_paths_keep_overrides(self):
        wid=self.plan()
        active=storage.build_active_workout(storage.read_workout(wid))
        for row in active['rows']: row.update(completed=True,weight='50',reps='12',rir='2')
        storage.save_active_workout(active)
        storage.import_data_zip_bytes(storage.export_data_zip_bytes())
        loaded=storage.load_active_workout()
        self.assertEqual([set_context.template_key(r) for r in active['rows']],[set_context.template_key(r) for r in loaded['rows']])
        storage.finish_active_workout(loaded)
        session=storage.read_session(active['session_id'])
        storage.save_session(session['session_id'],'Corrected name',session['rows'])
        storage.change_weight_unit('lb')
        storage.import_data_zip_bytes(storage.export_data_zip_bytes())
        plan=storage.read_workout(wid)['exercises'][0]['sets']
        history=storage.read_session(session['session_id'])['rows']
        self.assertEqual([set_context.template_key(r) for r in plan],[set_context.template_key(r) for r in history])
        self.assertAlmostEqual(110.23,float(history[0]['weight']),places=1)
        self.assertTrue(all(r['context_override']=='1' for r in history))

    def test_completed_explicit_variants_update_only_matching_planned_defaults(self):
        wid=self.plan(warmup=True)
        active=storage.build_active_workout(storage.read_workout(wid))
        for row in active['rows']: row.update(completed=True,weight='60',reps='10',rir='2')
        storage.save_active_workout(active)
        self.details(setup='Station B')
        # Correcting one performed variant must not seed another planned variation.
        active['rows'][2]['setup']='Different actual setup'
        storage.finish_active_workout(active)
        plan=storage.read_workout(wid)['exercises'][0]['sets']
        self.assertEqual('',plan[0]['weight'])
        self.assertEqual('60',plan[1]['weight'])
        self.assertEqual('50',plan[2]['weight'])
        self.assertEqual('60',plan[3]['weight'])

    def test_save_for_next_time_retains_inheritance_instead_of_freezing_old_defaults(self):
        wid=self.plan(warmup=True)
        active=storage.build_active_workout(storage.read_workout(wid))
        self.details(setup='Station B')
        WorkoutMixin.save_active_structure_for_next_time(SimpleNamespace(active_workout=active))
        plan=storage.read_workout(wid)['exercises'][0]['sets']
        self.assertEqual('',plan[0]['context_override'])
        self.assertEqual('',plan[0]['setup'])
        self.assertEqual('1',plan[1]['context_override'])
        self.assertEqual('High handle',plan[1]['setup'])
        self.assertEqual('Station B',storage.build_active_workout(storage.read_workout(wid))['rows'][0]['setup'])

    def test_mechanical_progression_remains_manual_for_known_distinct_variations(self):
        wid=self.plan()
        rows=storage.build_active_workout(storage.read_workout(wid))['rows'][:3]
        for row in rows: row.update(completed=True,weight='50',reps='13',rir='2',planned_work_count='3',stop_reason='target_rir',actual_rest_seconds=str(row['rest_seconds']))
        result=progression.method_progression_recommendation(rows,method='Mechanical Drop Set',target_rir=2,planned_rows=copy.deepcopy(rows))
        self.assertFalse(result['apply_weight'])
        self.assertEqual('hold',result['action'])
        self.assertIn('leverage',result['reason'])

    def test_invalid_template_flags_or_enums_roll_back_imports(self):
        self.plan()
        for key,value in [('context_override','2'),('side','invented'),('load_convention','invented'),('rep_convention','invented')]:
            rows=storage._read_csv(storage.WORKOUT_SET_TEMPLATES_FILE)
            rows[-1][key]=value
            before=self.snapshot()
            with self.subTest(key=key),self.assertRaises(ValueError):
                storage.import_data_zip_bytes(self.rewrite_archive('workout_set_templates.csv',self.csv_bytes(storage.TEMPLATE_SET_FIELDS,rows)))
            self.assertEqual(before,self.snapshot())

    def test_missing_legacy_template_context_columns_inherit_existing_defaults(self):
        wid=self.plan()
        rows=storage._read_csv(storage.WORKOUT_SET_TEMPLATES_FILE)
        fields=[key for key in storage.TEMPLATE_SET_FIELDS if key not in {'context_override',*set_context.FIELDS}]
        storage.import_data_zip_bytes(self.rewrite_archive('workout_set_templates.csv',self.csv_bytes(fields,[{key:r[key] for key in fields} for r in rows])))
        plan=storage.read_workout(wid)['exercises'][0]['sets']
        self.assertTrue(all(r['context_override']=='' for r in plan))
        self.assertEqual({'Station A'},{r['setup'] for r in storage.build_active_workout(storage.read_workout(wid))['rows']})

    def test_save_for_next_time_clears_presets_when_explicit_variant_changes(self):
        wid=self.plan()
        active=storage.build_active_workout(storage.read_workout(wid))
        active['rows'][1]['setup']='Other handle'
        active['rows'][1].update(weight='60',reps='10')
        observed=copy.deepcopy(active['rows'])
        WorkoutMixin.save_active_structure_for_next_time(SimpleNamespace(active_workout=active))
        plan=storage.read_workout(wid)['exercises'][0]['sets']
        self.assertEqual('Other handle',plan[1]['setup'])
        self.assertEqual(('', ''),(plan[1]['weight'],plan[1]['reps']))
        self.assertEqual('50',plan[0]['weight'])
        self.assertEqual(observed,active['rows'])

    def test_load_mode_changes_still_clear_explicit_variant_load_presets(self):
        wid=self.plan()
        storage.save_exercise_details(self.name,['Chest'],[],'','',load_mode='assisted',logging_context=self.base)
        plan=storage.read_workout(wid)['exercises'][0]['sets']
        self.assertEqual(['']*6,[r['weight'] for r in plan])
        self.assertEqual(['12']*6,[r['reps'] for r in plan])
        self.assertEqual(['High handle','Middle handle','Low handle']*2,[r['setup'] for r in plan])
