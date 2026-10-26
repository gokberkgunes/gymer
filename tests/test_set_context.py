"""Declared conventions survive persistence and prevent incompatible comparisons."""
import copy
from test_data_integrity import TemporaryStorageTestCase
import storage
import progression
import set_context


class SetContextTests(TemporaryStorageTestCase):
    context={'setup':'Machine A / seat 3','side':'bilateral','load_convention':'total','rep_convention':'total'}

    def save_details(self, **changes):
        context={**self.context,**changes}
        storage.save_exercise_details('Context exercise',['Chest'],[],'','',logging_context=context)
        return context

    def plan(self):
        self.save_details()
        wid=storage.create_workout('Context plan')
        storage.save_workout(wid,'Context plan',[{'exercise_name':'Context exercise','training_method':'Straight',
            'sets':[{'set_type':'Normal','weight':'20','reps':'12','rest_seconds':60} for _ in range(2)]}])
        return wid

    def observations(self):
        return [{**self.context,'exercise_name':'Context exercise','set_number':i+1,'set_type':'Normal',
                 'weight':'20','reps':'12','rir':'2','completed':True,'load_mode':'external'} for i in range(2)]

    def test_defaults_snapshot_without_inference_or_numeric_conversion(self):
        wid=self.plan()
        self.save_details(side='left',load_convention='per_implement',rep_convention='per_side')
        active=storage.build_active_workout(storage.read_workout(wid))
        for row in active['rows']:
            self.assertEqual('left',row['side'])
            self.assertEqual('per_implement',row['load_convention'])
            self.assertEqual('per_side',row['rep_convention'])
            self.assertEqual('',row['previous_weight'])
        legacy=storage.read_exercise_details('Dumbbell mystery')
        self.assertEqual(dict.fromkeys(set_context.FIELDS,''),set_context.metadata(legacy))

    def test_changed_defaults_clear_future_presets_and_freeze_active_context(self):
        wid=self.plan()
        active=storage.build_active_workout(storage.read_workout(wid))
        for row in active['rows']: row.update(completed=True,weight='20',reps='12',rir='2')
        storage.save_active_workout(active)
        before=copy.deepcopy(storage.load_active_workout())
        self.save_details(setup='Machine B')
        self.assertEqual(before,storage.load_active_workout())
        for row in storage.read_workout(wid)['exercises'][0]['sets']:
            self.assertEqual(('', ''),(row['weight'],row['reps']))
        storage.finish_active_workout(active)
        self.assertTrue(all(row['weight']==row['reps']=='' for row in storage.read_workout(wid)['exercises'][0]['sets']))
        self.assertEqual({'Machine A / seat 3'},{row['setup'] for row in storage.read_session(active['session_id'])['rows']})
        new=storage.build_active_workout(storage.read_workout(wid))
        self.assertTrue(all(row['previous_weight']==row['previous_reps']=='' for row in new['rows']))

    def test_context_round_trip_active_history_correction_backup_and_units(self):
        wid=self.plan()
        context=self.save_details(side='left',load_convention='per_implement',rep_convention='per_side')
        active=storage.build_active_workout(storage.read_workout(wid))
        for row in active['rows']: row.update(completed=True,weight='20',reps='12',rir='2')
        storage.save_active_workout(active)
        storage.import_data_zip_bytes(storage.export_data_zip_bytes())
        loaded=storage.load_active_workout()
        self.assertTrue(all(set_context.matches(row,context) for row in loaded['rows']))
        storage.finish_active_workout(loaded)
        session=storage.read_session(active['session_id'])
        session['rows'][1]['side']='right'
        storage.save_session(session['session_id'],'Corrected side',session['rows'])
        storage.change_weight_unit('lb')
        storage.import_data_zip_bytes(storage.export_data_zip_bytes())
        rows=storage.read_session(session['session_id'])['rows']
        self.assertEqual(['left','right'],[row['side'] for row in rows])
        self.assertTrue(all(row['load_convention']=='per_implement' and row['rep_convention']=='per_side' for row in rows))
        self.assertAlmostEqual(44.09,float(rows[0]['weight']),places=1)
        self.assertEqual(['12','12'],[row['reps'] for row in rows])

    def test_matching_straight_context_progresses_in_its_logged_basis(self):
        rows=self.observations()
        for row in rows: row.update(load_convention='per_implement',side='left',rep_convention='per_side')
        result=progression.method_progression_recommendation(rows,method='Straight',target_rir=2,weight_increment=2,planned_rows=copy.deepcopy(rows))
        self.assertEqual('increase',result['action'])
        self.assertEqual(22,result['weight'])
        self.assertTrue(result['apply_weight'])

    def test_each_changed_or_unknown_current_convention_blocks_straight_automation(self):
        rows=self.observations()
        for key,value in [('setup','Machine B'),('side','right'),('load_convention','per_implement'),('rep_convention','per_side'),('side','')]:
            plan=copy.deepcopy(rows)
            for row in plan: row[key]=value
            result=progression.method_progression_recommendation(rows,method='Straight',target_rir=2,weight_increment=2,planned_rows=plan)
            with self.subTest(key=key,value=value):
                self.assertFalse(result['apply_weight'])
                self.assertEqual('hold',result['action'])
                self.assertIsNone(result['estimated_1rm'])
                self.assertIn('conventions',result['reason'])

    def test_mixed_left_right_or_setups_stay_manual_without_pairing_or_combining(self):
        rows=self.observations()
        rows[0]['side']='left'
        rows[1]['side']='right'
        before=copy.deepcopy(rows)
        result=progression.progression_recommendation(rows,target_rir=2)
        self.assertFalse(result['apply_weight'])
        self.assertEqual(before,rows)
        self.assertTrue(set_context.comparison_error(rows,rows))
        blank=[{key:value for key,value in row.items() if key not in set_context.FIELDS} for row in rows]
        self.assertEqual('',set_context.comparison_error(blank,blank))

    def test_new_convention_enum_import_is_validated_without_partial_mutation(self):
        wid=self.plan()
        active=storage.build_active_workout(storage.read_workout(wid))
        storage.save_active_workout(active)
        for filename,fields in [('exercise_details.csv',storage.EXERCISE_DETAIL_FIELDS),('active_workout.csv',storage.ACTIVE_FIELDS)]:
            for key in set_context.OPTIONS:
                rows=storage._read_csv(storage.DATA_DIR / filename)
                rows[0][key]='invented'
                before=self.snapshot()
                with self.assertRaises(ValueError):
                    storage.import_data_zip_bytes(self.rewrite_archive(filename,self.csv_bytes(fields,rows)))
                self.assertEqual(before,self.snapshot())

    def test_legacy_missing_columns_stay_unknown(self):
        wid=self.plan()
        source=storage._read_csv(storage.EXERCISE_DETAILS_FILE)
        fields=[key for key in storage.EXERCISE_DETAIL_FIELDS if key not in set_context.FIELDS]
        storage.import_data_zip_bytes(self.rewrite_archive('exercise_details.csv',self.csv_bytes(fields,[{key:row[key] for key in fields} for row in source])))
        self.assertEqual(dict.fromkeys(set_context.FIELDS,''),set_context.metadata(storage.read_exercise_details('Context exercise')))

    def test_invalid_direct_default_context_does_not_change_files(self):
        self.plan()
        before=self.snapshot()
        with self.assertRaises(ValueError): self.save_details(side='invented')
        self.assertEqual(before,self.snapshot())

    def test_combined_side_entry_requires_manual_progression_even_when_context_matches(self):
        rows=self.observations()
        for row in rows: row['side']='both_separately'
        result=progression.method_progression_recommendation(rows,method='Straight',target_rir=2,planned_rows=copy.deepcopy(rows))
        self.assertFalse(result['apply_weight'])
        self.assertIsNone(result['estimated_1rm'])
        self.assertIn('manual progression',result['reason'])
