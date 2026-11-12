"""Protecciones del ejecutor local, sin necesitar un servidor."""
import sys
import unittest
import subprocess
from unittest.mock import Mock
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import manage
from concurrencia import Transaction


class Protecciones(unittest.TestCase):
    def test_no_elimina_la_base_de_trabajo(self):
        for name in ('banco_proyectos', 'postgres', 'otro_proyecto', 'banco_proyectos_test_'):
            with self.subTest(name=name), self.assertRaises(ValueError):
                manage.require_temporary_database(name)

    def test_acepta_solo_bases_temporales_propias(self):
        manage.require_temporary_database('banco_proyectos_test_012345abcdef')
        with self.assertRaises(ValueError):
            manage.require_temporary_database('banco_proyectos_test_012345abcdef; DROP DATABASE postgres')

    def test_no_interpreta_un_nombre_como_sql(self):
        self.assertEqual(manage.sql_identifier('a"b'), '"a""b"')
        self.assertEqual(manage.sql_literal("O'Brien"), "'O''Brien'")

    def test_rechaza_conninfo_y_uri_como_nombre_de_base(self):
        for value in ('postgresql://servidor/base', 'host=remoto dbname=base', 'base con espacios', 'base\notra', '', 'a'*64):
            with self.subTest(value=value), self.assertRaises(ValueError):
                manage.require_database_name(value)

    def test_nombre_local_valido(self):
        manage.require_database_name('banco_proyectos')
        manage.require_database_name('banco_proyectos_test_012345abcdef')

    def test_recolecta_la_conexion_si_falla_el_cierre(self):
        tx = Transaction.__new__(Transaction)
        tx.process = Mock()
        tx.process.poll.return_value = None
        tx.reader = Mock()
        tx.execute = Mock(side_effect=subprocess.TimeoutExpired('psql', 20))
        with self.assertRaises(subprocess.TimeoutExpired):
            tx.close()
        tx.process.kill.assert_called_once()
        self.assertTrue(tx.process.wait.called)
        tx.reader.join.assert_called_once()
        tx.process.stdout.close.assert_called_once()
        tx.process.stderr.close.assert_called_once()

    def test_envia_eof_antes_de_esperar_psql(self):
        tx = Transaction.__new__(Transaction)
        tx.process = Mock()
        tx.process.poll.return_value = None
        tx.process.stdin.closed = False
        tx.reader = Mock()
        tx.execute = Mock()
        def wait(**kwargs):
            self.assertTrue(tx.process.stdin.close.called, 'psql espera EOF para terminar')
            return 0
        tx.process.wait.side_effect = wait
        tx.close(commit=True)


if __name__ == '__main__':
    unittest.main()
