"""Explicit protocol boundaries survive authored and observed storage paths."""
import copy
from test_data_integrity import TemporaryStorageTestCase
import storage
import progression
import volume_accounting
from types import SimpleNamespace
from workouts import WorkoutMixin


class ProtocolGroupTests(TemporaryStorageTestCase):
    def plan(self, method='Myo-Reps'):
        rows = [{'set_type':'Normal','weight':str(50 + index),'reps':'10',
                 'rest_seconds':120 if index == 1 else 20,
                 'protocol_group_start':'1' if index == 2 else ''} for index in range(5)]
        return {'exercise_name':'Grouped exercise','training_method':method,
                'sets':storage.reconcile_method_sets(method, rows)}

    def save_plan(self, method='Myo-Reps'):
        wid = storage.create_workout('Two protocol groups')
        storage.save_workout(wid, 'Two protocol groups', [self.plan(method)])
        return wid

    def test_roles_restart_only_at_explicit_boundaries_and_keep_authored_values(self):
        for method, follow in storage.ACTIVATION_FOLLOWUP.items():
            plan = self.plan(method)
            self.assertEqual(['Activation',follow,'Activation',follow,follow],
                             [row['set_type'] for row in plan['sets']])
            self.assertTrue(storage.validate_method_sets(method, plan['sets'])[0])
            self.assertEqual(['Activation'], storage.set_type_choices_for_method_row(method, plan['sets'], 2))
            self.assertEqual([str(50 + i) for i in range(5)], [r['weight'] for r in plan['sets']])
            self.assertEqual(120, plan['sets'][1]['rest_seconds'])
            plan['sets'][2]['protocol_group_start']=''
            joined = storage.reconcile_method_sets(method, plan['sets'])
            self.assertEqual(['Activation']+[follow]*4, [row['set_type'] for row in joined])

    def test_legacy_plans_and_warmups_keep_one_group_without_rewriting_input(self):
        source=[{'set_type':'Warm-up','protocol_group_start':'1'}]+[{'set_type':'Normal'} for _ in range(4)]
        before=copy.deepcopy(source)
        rows=storage.reconcile_method_sets('Myo-Reps',source)
        self.assertEqual(before,source)
        self.assertEqual(['Warm-up','Activation','Myo-set','Myo-set','Myo-set'],[row['set_type'] for row in rows])
        self.assertEqual('',rows[0]['protocol_group_start'])
        self.assertEqual(1,storage.workout_volume_report([{'exercise_name':'Legacy','training_method':'Myo-Reps','sets':rows}])['totals']['protocol_groups'])

    def test_cluster_and_activation_groups_get_independent_runtime_ids_and_sizes(self):
        for method in ('Cluster','Myo-Reps'):
            wid=self.save_plan(method)
            workout=storage.read_workout(wid)
            first=storage.build_active_workout(workout)['rows']
            second=storage.build_active_workout(workout)['rows']
            self.assertEqual(2,len({r['group_id'] for r in first}))
            self.assertEqual(['2','2','3','3','3'],[r['group_planned_count'] for r in first])
            self.assertTrue({r['group_id'] for r in first}.isdisjoint({r['group_id'] for r in second}))
            self.assertEqual(['','','1','',''],[r['protocol_group_start'] for r in first])
            self.assertEqual(2,storage.workout_volume_report(workout['exercises'])['totals']['complete_protocol_groups'])

    def test_partial_completion_and_removed_segments_do_not_merge_or_shrink_groups(self):
        wid=self.save_plan('Cluster')
        rows=storage.build_active_workout(storage.read_workout(wid))['rows']
        for row in rows: row['completed']=True
        rows[-1]['completed']=False
        report=storage.volume_report(rows)['totals']
        self.assertEqual((2,1,1),(report['protocol_groups'],report['complete_protocol_groups'],report['partial_protocol_groups']))
        rows.pop()
        storage.initialize_volume_rows(rows)
        self.assertEqual('3',rows[-1]['group_planned_count'])
        report=storage.volume_report(rows)['totals']
        self.assertEqual((2,1,1),(report['protocol_groups'],report['complete_protocol_groups'],report['partial_protocol_groups']))

    def test_template_active_history_edit_and_backup_round_trip_preserve_boundaries(self):
        wid=self.save_plan()
        before=storage.read_workout(wid)
        active=storage.build_active_workout(before)
        for row in active['rows']:
            row.update(completed=True,weight='50',reps='13',rir='2',setup='Machine A',stop_reason='target_rir',actual_rest_seconds=str(row['rest_seconds']))
        original=copy.deepcopy(active['rows'])
        storage.save_active_workout(active)
        storage.import_data_zip_bytes(storage.export_data_zip_bytes())
        loaded=storage.load_active_workout()
        self.assertEqual([r['group_id'] for r in original],[r['group_id'] for r in loaded['rows']])
        self.assertEqual(['','','1','',''],[r['protocol_group_start'] for r in loaded['rows']])
        storage.finish_active_workout(loaded)
        session=storage.read_session(active['session_id'])
        storage.save_session(session['session_id'],'Edited history',session['rows'])
        storage.import_data_zip_bytes(storage.export_data_zip_bytes())
        saved=storage.read_session(session['session_id'])['rows']
        self.assertEqual(['','','1','',''],[r['protocol_group_start'] for r in saved])
        self.assertEqual(['2','2','3','3','3'],[r['group_planned_count'] for r in saved])
        self.assertEqual(120,int(saved[1]['rest_seconds']))
        # Performed defaults may change; authored boundaries and rests do not.
        after=storage.read_workout(wid)['exercises'][0]['sets']
        self.assertEqual(['','','1','',''],[r['protocol_group_start'] for r in after])
        self.assertEqual(120,after[1]['rest_seconds'])

    def test_multi_group_progression_stays_manual_even_with_complete_observations(self):
        wid=self.save_plan()
        rows=storage.build_active_workout(storage.read_workout(wid))['rows']
        for row in rows:
            row.update(completed=True,weight='100',reps='13',rir='2',setup='Machine A',stop_reason='target_rir',actual_rest_seconds=str(row['rest_seconds']))
        result=progression.method_progression_recommendation(rows,method='Myo-Reps',target_rir=2,weight_increment=5)
        self.assertFalse(result['apply_weight'])
        self.assertIn('multiple protocol groups',result['reason'])

    def test_irrelevant_boundaries_clear_on_method_change(self):
        for method in ('Straight','AMRAP'):
            rows=storage.reconcile_method_sets(method,self.plan()['sets'])
            self.assertTrue(all(row['protocol_group_start']=='' for row in rows))
            self.assertTrue(storage.validate_method_sets(method,rows)[0])

    def test_changed_cluster_plan_cannot_reuse_single_group_progression(self):
        wid=self.save_plan('Cluster')
        planned=storage.build_active_workout(storage.read_workout(wid))['rows']
        rows=copy.deepcopy(planned)
        for row in rows:
            row.update(group_id='old-single-group',group_planned_count='5',protocol_group_start='',
                       completed=True,weight='100',reps='6',setup='Machine A',actual_rest_seconds=str(row['rest_seconds']))
        result=progression.method_progression_recommendation(rows,method='Cluster',target_rir=2,weight_increment=5,planned_rows=planned)
        self.assertFalse(result['apply_weight'])
        self.assertIn('multiple protocol groups',result['reason'])

    def test_save_for_next_time_retains_group_identity_after_boundary_fragment_is_removed(self):
        wid=self.save_plan('Cluster')
        active=storage.build_active_workout(storage.read_workout(wid))
        active['rows'].pop(2)  # Remove the explicitly marked first fragment of group 2.
        before=copy.deepcopy(active['rows'])
        WorkoutMixin.save_active_structure_for_next_time(SimpleNamespace(active_workout=active))
        planned=storage.read_workout(wid)['exercises'][0]['sets']
        self.assertEqual(['','','1',''],[row['protocol_group_start'] for row in planned])
        self.assertEqual(before,active['rows'])
        self.assertEqual('3',active['rows'][-1]['group_planned_count'])

    def test_recovery_conversion_clears_protocol_boundaries(self):
        wid=self.save_plan('Cluster')
        workout=storage.read_workout(wid)
        rows=storage.build_active_workout(workout)['rows']
        cycle=storage.save_mesocycle({'setup_complete':'1','deload_policy':'recovery'})
        context={'cycle_id':cycle,'cycle_target_rir':'4'}
        recovery=storage._build_deload_rows(workout,rows,context)
        self.assertTrue(recovery)
        self.assertTrue(all(row['training_method']=='Straight' and row['protocol_group_start']=='' for row in recovery))

    def test_invalid_boundary_import_rolls_back_and_legacy_templates_stay_compatible(self):
        wid=self.save_plan()
        before=self.snapshot()
        rows=storage._read_csv(storage.WORKOUT_SET_TEMPLATES_FILE)
        rows[-1]['protocol_group_start']='2'
        with self.assertRaisesRegex(ValueError,'protocol_group_start'):
            storage.import_data_zip_bytes(self.rewrite_archive('workout_set_templates.csv',self.csv_bytes(storage.TEMPLATE_SET_FIELDS,rows)))
        self.assertEqual(before,self.snapshot())
        fields=[key for key in storage.TEMPLATE_SET_FIELDS if key!='protocol_group_start']
        rows=storage._read_csv(storage.WORKOUT_SET_TEMPLATES_FILE)
        storage.import_data_zip_bytes(self.rewrite_archive('workout_set_templates.csv',self.csv_bytes(fields,[{key:row[key] for key in fields} for row in rows])))
        legacy=storage.read_workout(wid)
        self.assertTrue(all(row['protocol_group_start']=='' for row in legacy['exercises'][0]['sets']))
