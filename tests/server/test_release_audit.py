import io
import hashlib
import json
from pathlib import Path
import sys
import tarfile
import unittest
import zipfile
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'scripts'))
from audit_release import Audit


class ReleaseAuditChecks(unittest.TestCase):
    def test_nested_archive_findings_do_not_echo_credentials(self):
        secret = 'sk-' + 'a' * 40
        raw = b'/home/example-user/build/source.cpp\n' + secret.encode()
        tar = io.BytesIO()
        with tarfile.open(fileobj=tar, mode='w:gz') as bundle:
            item = tarfile.TarInfo('runtime/test.bin'); item.size = len(raw)
            bundle.addfile(item, io.BytesIO(raw))
        output = io.BytesIO()
        with zipfile.ZipFile(output, 'w') as bundle: bundle.writestr('runtime.tar.gz', tar.getvalue())
        audit = Audit(); audit.check('release.zip', output.getvalue())
        self.assertEqual({f['kind'] for f in audit.findings}, {'personal-source-path', 'credential-pattern'})
        self.assertNotIn(secret, json.dumps(audit.findings))
        self.assertTrue(all('runtime/test.bin' in f['file'] for f in audit.findings))

    def test_public_defaults_are_not_private_setup(self):
        audit = Audit()
        audit.check('config.json', b'{"host":"127.0.0.1","port":18792,"native_port":18797}')
        self.assertFalse(audit.findings)

    def test_expansion_limit_cannot_silently_report_clean(self):
        audit = Audit(max_bytes=4)
        with self.assertRaises(ValueError): audit.check('oversized', b'12345')

    def test_vendor_reference_exemption_requires_exact_bytes(self):
        raw = b'upstream address constant: 192.168.0.0/16'
        digest = hashlib.sha256(raw).hexdigest()
        with patch.dict('audit_release.PUBLIC_RUNTIME_REFERENCES', {digest: 'verified upstream fixture'}):
            original = Audit(); original.check('runtime.pyc', raw)
            self.assertFalse(original.findings)
            self.assertEqual(len(original.public_runtime_references), 1)
            changed = Audit(); changed.check('runtime.pyc', raw + b'changed')
            self.assertEqual(changed.findings[0]['kind'], 'private-network-address')

    def test_credentials_are_never_exempted_as_vendor_references(self):
        raw = ('sk-' + 'a' * 40).encode()
        with patch.dict('audit_release.PUBLIC_RUNTIME_REFERENCES', {hashlib.sha256(raw).hexdigest(): 'fixture'}):
            audit = Audit(); audit.check('runtime', raw)
            self.assertEqual(audit.findings[0]['kind'], 'credential-pattern')
