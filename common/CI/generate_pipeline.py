#!/usr/bin/env python3
import argparse
import logging
import os.path
from dataclasses import dataclass
from typing import Dict, Iterator, List, Optional

import yaml
from package_checks import Git, LogFormatter

LOCAL_DIR = '/var/lib/solbuild/local/'
FERRYD_USER = os.environ.get('FERRYD_USER', 'invalid')
FERRYD_HOST = os.environ.get('FERRYD_HOST', 'invalid')
FERRYD_PATH = os.environ.get("FERRYD_PATH", '/invalid')
SOLBUILD_FLAGS = [
    '--debug',
    '--tmpfs',
    '--memory 16G',
    '--disable-abi-report',
    '--no-color',
    '--profile local-unstable-x86_64',
    '--transit-manifest unstable',
]


def getenv(*names: str, default: Optional[str] = None) -> Optional[str]:
    for var in names:
        if var in os.environ:
            return os.environ[var]

    return default


def on_main() -> bool:
    branch = getenv('CI_COMMIT_BRANCH')
    default = getenv('CI_DEFAULT_BRANCH')

    return branch is not None and branch == default


@dataclass
class Job:
    package: str
    needs: List[str]

    @property
    def _dir(self) -> str:
        return os.path.join('packages', self._subdir, self.package)

    @property
    def _subdir(self) -> str:
        for two in ['py']:
            if self.package.startswith(two):
                return two

        return self.package[0]

    @property
    def _build_target(self) -> str:
        yml = os.path.join(self._dir, "package.yml")
        spec = os.path.join(self._dir, "pspec.xml")

        if os.path.exists(yml):
            return yml
        if os.path.exists(spec):
            return spec

        raise ValueError(f'invalid package: {self.package}')

    @property
    def _build_steps(self) -> List[str]:
        return [
            f'rm -rf {LOCAL_DIR}/*',
            f'mv -v *.eopkg {LOCAL_DIR}/ || true',
            # f'eopkg index --skip-signing {LOCAL_DIR} --output {LOCAL_DIR}/eopkg-index.xml',
            f'sudo solbuild build {" ".join(SOLBUILD_FLAGS)} {self._build_target}',
        ]

    def gitlab(self) -> Dict[str, object]:
        return {
            'stage': 'build',
            'tags': ['shell'],
            'needs': self.needs,
            'script': self._build_steps,
            'artifacts': {
                'paths': ['*.eopkg', '*.tram'],
                'expire_in': '1 hour',
            },
        }


class NoAliasDumper(yaml.SafeDumper):
    def ignore_aliases(self, data: object) -> bool:
        return True


class Generator:
    def __init__(self, path: str, target: Optional[str], head: str):
        self.git = Git(path)

        if target is None:
            target = self.__resolve_target()

        self.base = self.git.merge_base(head, target)
        self.head = head

    def _packages_in_order(self) -> Iterator[str]:
        refs = self.git.commit_refs(self.base, self.head)
        refs.reverse()

        for ref in refs:
            package = self._package(self.git.files_in_commit(ref))
            if package:
                yield package

    @staticmethod
    def _package(files: List[str]) -> Optional[str]:
        for file in files:
            if os.path.basename(file) in ['pspec_x86_64.xml', 'pspec.xml']:
                return os.path.basename(os.path.dirname(file))

        return None

    def generate_gitlab(self, output: str, upload: bool) -> None:
        needs: List[str] = []
        config: Dict[str, object] = {
            'workflow': {
                'rules': [
                    {'if': "$CI_PIPELINE_SOURCE == 'parent_pipeline'"},
                ],
            }
        }

        for package in self._packages_in_order():
            config[package] = Job(package, needs.copy()).gitlab()
            needs.append(package)

        if upload:
            config['deploy'] = self._upload_job(needs)

        with open(output, 'w') as o:
            o.write(yaml.dump(config, Dumper=NoAliasDumper))

    def _upload_job(self, needs: List[str]) -> Dict[str, object]:
        return {
            'stage': 'deploy',
            'needs': needs,
            'tags': ['shell'],
            'script': [
                f'/usr/bin/scp *.eopkg *.tram "{FERRYD_USER}@{FERRYD_HOST}:{FERRYD_PATH}"'
            ],
        }

    def __resolve_target(self) -> str:
        mr_target_sha = getenv('CI_MERGE_REQUEST_TARGET_BRANCH_SHA',
                               'CI_EXTERNAL_PULL_REQUEST_TARGET_BRANCH_SHA')
        commit_before_sha = getenv('CI_COMMIT_BEFORE_SHA')
        default_branch = getenv('CI_DEFAULT_BRANCH') or 'main'

        if mr_target_sha is not None:
            return mr_target_sha

        if on_main() and commit_before_sha is not None:
            return commit_before_sha

        logging.info(f'Fetching origin/{default_branch}')
        self.git.fetch(['origin', default_branch])

        return f'origin/{default_branch}'


if __name__ == "__main__":
    logging.basicConfig(level=logging.DEBUG, handlers=[LogFormatter.handler()])

    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=str,
                        help='Output file')
    parser.add_argument('--target', type=str,
                        default=None,
                        help='Optional name of the target branch')
    parser.add_argument('--deploy', action='store_true',
                        default=on_main(),
                        help='Deploy packages after building')

    cli_args = parser.parse_args()

    generator = Generator(path='.', target=cli_args.target, head='HEAD')
    generator.generate_gitlab(cli_args.output, cli_args.deploy)
