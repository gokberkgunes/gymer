"""Rest-after categories do not rewrite completed plans or infer missing groups."""
import copy
import unittest
from test_data_integrity import TemporaryStorageTestCase
import rest_scopes
import storage
import volume_accounting


class RestScopeTests(TemporaryStorageTestCase):
    def rows(self):
        rows=[]
        for number, kind in enumerate(['Warm-up','Normal','Activation','Myo-set','Myo-set','Activation','Myo-set','Myo-set'],1):
            rows.append(dict(exercise_name='Mixed',set_number=number,set_type=kind,completed=False,
                             rest_seconds=120 if number in (2,5,8) else 20,
                             protocol_group_start='1' if number==6 else '',actual_rest_seconds='17'))
        return volume_accounting.assign_groups(rows)

    def test_warmup_conventional_intra_and_after_group_targets_are_distinct(self):
        rows=self.rows()
        before=copy.deepcopy(rows)
        options=rest_scopes.targets(rows)
        self.assertEqual([1],options['warmup'])
        self.assertEqual([2],options['conventional'])
        self.assertEqual([3,4,6,7],options['within_protocol'])
        self.assertEqual([5,8],options['after_protocol'])
        self.assertEqual(list(range(1,9)),options['all_pending'])
        self.assertEqual([6],options['set:6'])
        self.assertEqual(before,rows)

    def test_completed_rows_are_excluded_without_moving_group_boundaries(self):
        rows=self.rows()
        for index in (0,2,4): rows[index]['completed']=True
        options=rest_scopes.targets(rows)
        self.assertNotIn('warmup',options)
        self.assertEqual([4,6,7],options['within_protocol'])
        self.assertEqual([8],options['after_protocol'])
        self.assertEqual([2,4,6,7,8],options['all_pending'])
        self.assertNotIn('set:5',options)
        for row in rows: row['completed']='1'
        self.assertEqual({},rest_scopes.targets(rows))

    def test_cluster_groups_use_recorded_boundaries(self):
        rows=[dict(exercise_name='Cluster',set_number=i+1,set_type='Cluster Set',completed=False,
                   protocol_group_start='1' if i==2 else '') for i in range(5)]
        volume_accounting.assign_groups(rows)
        options=rest_scopes.targets(rows)
        self.assertEqual([1,3,4],options['within_protocol'])
        self.assertEqual([2,5],options['after_protocol'])

    def test_missing_removed_or_inconsistent_segments_remain_individually_editable(self):
        for change in ('removed','roles','sizes','noncontiguous','boundary'):
            rows=self.rows()[2:5]
            if change=='removed': rows.pop()
            elif change=='roles': rows[1]['segment_role']='anchor'
            elif change=='sizes': rows[1]['group_planned_count']='4'
            elif change=='noncontiguous': rows.insert(1,dict(exercise_name='Mixed',set_number=99,set_type='Normal',completed=False))
            elif change=='boundary': rows[1]['protocol_group_start']='1'
            with self.subTest(change=change):
                options=rest_scopes.targets(rows)
                self.assertNotIn('within_protocol',options)
                self.assertNotIn('after_protocol',options)
                self.assertIn('all_pending',options)
                self.assertIn('set:3',options)

    def test_legacy_rows_do_not_gain_inferred_protocol_rest_categories(self):
        rows=[dict(exercise_name='Legacy',set_number=i+1,set_type=kind,completed=False)
              for i,kind in enumerate(['Activation','Myo-set','Myo-set'])]
        options=rest_scopes.targets(rows)
        self.assertEqual({'all_pending','set:1','set:2','set:3'},set(options))
        self.assertFalse(any('group_id' in row for row in rows))

    def test_strict_duration_accepts_zero_and_valid_seconds_or_minutes(self):
        for value,expected in [('0',0),('0:00',0),('90',90),('90.0',90),(' 1:30 ',90),('1440:00',86400),('86400',86400)]:
            self.assertEqual(expected,rest_scopes.duration(value))

    def test_invalid_durations_do_not_silently_fall_back(self):
        for value in ('',None,'-1','1.5','nan','inf','1:60','1:2','1:02:03','90s','86401','1440:01','9'*5000):
            with self.subTest(value=str(value)[:20]),self.assertRaises(ValueError):
                rest_scopes.duration(value)

    def test_shared_duration_parser_preserves_numeric_zero(self):
        for value in (0, 0.0, '0', '0:00'):
            self.assertEqual(0,storage.parse_duration(value,default=180))
            self.assertEqual('0:00',storage.format_duration(value))
        for value in ('', None, 'nan', 'inf', '-inf'):
            self.assertEqual(180,storage.parse_duration(value,default=180))

    def test_zero_planned_rests_survive_template_active_backup_and_rebuild(self):
        wid=storage.create_workout('Zero rests')
        storage.save_workout(wid,'Zero rests',[{'exercise_name':'Zero exercise','training_method':'Straight',
            'sets':[{'set_type':'Normal','rest_seconds':value} for value in (0,0.0,'0','0:00')]}])
        workout=storage.read_workout(wid)
        self.assertEqual([0]*4,[row['rest_seconds'] for row in workout['exercises'][0]['sets']])
        active=storage.build_active_workout(workout)
        self.assertEqual([0]*4,[row['rest_seconds'] for row in active['rows']])
        storage.save_active_workout(active)
        storage.import_data_zip_bytes(storage.export_data_zip_bytes())
        self.assertEqual([0]*4,[row['rest_seconds'] for row in storage.load_active_workout()['rows']])

    def test_stale_selection_signature_tracks_completion_structure_and_planned_rest(self):
        rows=self.rows()
        original=rest_scopes.signature(rows)
        for key,value in [('completed',True),('rest_seconds',99),('group_id','changed'),('set_type','Normal'),('group_planned_count','9')]:
            changed=copy.deepcopy(rows)
            changed[2][key]=value
            self.assertNotEqual(original,rest_scopes.signature(changed))
        rows[2]['actual_rest_seconds']='99'
        self.assertEqual(original,rest_scopes.signature(rows))
