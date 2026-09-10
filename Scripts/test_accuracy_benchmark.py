import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from film_accuracy import delta_e_2000, score


class FilmAccuracyTests(unittest.TestCase):
    def test_published_ciede2000_pairs(self):
        # Sharma, Wu & Dalal supplementary test data, pairs 1, 2, 3, 7, 8.
        # https://hajim.rochester.edu/ece/sites/gsharma/ciede2000/
        for a, b, expected in [
            ((50, 2.6772, -79.7751), (50, 0, -82.7485), 2.0425),
            ((50, 3.1571, -77.2803), (50, 0, -82.7485), 2.8615),
            ((50, 2.8361, -74.0200), (50, 0, -82.7485), 3.4412),
            ((50, 0, 0), (50, -1, 2), 2.3669),
            ((50, -1, 2), (50, 0, 0), 2.3669),
        ]:
            self.assertAlmostEqual(delta_e_2000(a, b), expected, delta=.00005)
            self.assertAlmostEqual(delta_e_2000(a, b), delta_e_2000(b, a), places=12)

    def test_held_out_measurements_hashes_and_leakage(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def csv(name, lab):
                data = f'sample,L,a,b\ngray,{lab}\n'.encode()
                (root / name).write_bytes(data)
                return {'path': name, 'sha256': hashlib.sha256(data).hexdigest()}
            reference = csv('reference.csv', '50,0,0')
            candidate = csv('candidate.csv', '55,0,0')
            capture = dict(id='test', stock='test', batch='test', roll='roll1', scene='scene1',
                           process='test', illuminant='D65', exposure='0', scanner='locked',
                           inputKind='scene-linear-raw', split='validation', metric='deltaE00',
                           reference=reference, candidate=candidate)
            manifest = dict(schemaVersion=1, referenceWorkflow='test', inputTransform='test',
                            outputTransform='test', referenceWhite='D65', usageRights='test fixture', captures=[capture])
            path = root / 'manifest.json'
            def save():
                path.write_text(json.dumps(manifest))
            save()
            report = score(path)
            self.assertGreater(report['captures'][0]['summary']['median'], 4)
            self.assertEqual(report['status'], 'measured-no-acceptance-threshold')
            manifest['captures'].append(dict(capture, id='fit', split='calibration', scene='scene2'))
            save()
            with self.assertRaisesRegex(ValueError, 'leakage'):
                score(path)
            manifest['captures'] = [capture]
            save()
            (root / 'candidate.csv').write_text('sample,L,a,b\ngray,50,0,0\n')
            with self.assertRaisesRegex(ValueError, 'hash mismatch'):
                score(path)

    def test_no_reference_data_cannot_report_accuracy(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'manifest.json'
            path.write_text(json.dumps(dict(schemaVersion=1, referenceWorkflow='test', inputTransform='test',
                outputTransform='test', referenceWhite='D65', usageRights='test', captures=[])))
            with self.assertRaisesRegex(ValueError, 'No independent film captures'):
                score(path)


if __name__ == '__main__':
    unittest.main()
