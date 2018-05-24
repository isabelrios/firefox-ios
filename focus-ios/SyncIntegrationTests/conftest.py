import io
import json
import os
import time

from mozdownload import DirectScraper, FactoryScraper
from mozprofile import Profile
import mozinstall
import mozversion
import pytest

from tps import TPS
from xcodebuild import XCodeBuild

here = os.path.dirname(__file__)


@pytest.fixture(scope='session')
def firefox(pytestconfig, tmpdir_factory):
    binary = pytestconfig.getoption('firefox')
    if binary is None:
        cache_dir = str(pytestconfig.cache.makedir('firefox'))
        scraper = FactoryScraper('daily', destination=cache_dir)
        build_path = scraper.download()
        install_path = str(tmpdir_factory.mktemp('firefox'))
        install_dir = mozinstall.install(src=build_path, dest=install_path)
        binary = mozinstall.get_binary(install_dir, 'firefox')
    version = mozversion.get_version(binary)
    if hasattr(pytestconfig, '_metadata'):
        pytestconfig._metadata.update(version)
    return binary


@pytest.fixture
def firefox_log(pytestconfig, tmpdir):
    firefox_log = str(tmpdir.join('firefox.log'))
    pytestconfig._firefox_log = firefox_log
    yield firefox_log


@pytest.fixture(scope='session')
def tps_addon(pytestconfig, tmpdir_factory):
    url = 'https://index.taskcluster.net/v1/task/' \
          'gecko.v2.mozilla-central.latest.firefox.addons.tps/' \
          'artifacts/public/tps.xpi'
    path = pytestconfig.getoption('tps')
    if path is None:
        cache_dir = str(pytestconfig.cache.makedir('tps'))
        scraper = DirectScraper(url, destination=cache_dir)
        path = scraper.download()
    yield path


@pytest.fixture
def tps_config(fxa_account):
    yield {'fx_account': {
        'username': fxa_account.email,
        'password': fxa_account.password}}


@pytest.fixture
def tps_log(pytestconfig, tmpdir):
    tps_log = str(tmpdir.join('tps.log'))
    pytestconfig._tps_log = tps_log
    yield tps_log


@pytest.fixture
def tps_profile(pytestconfig, tps_addon, tps_config, tps_log, fxa_urls):
    preferences = {
        'browser.onboarding.enabled': False,
        'browser.startup.homepage_override.mstone': 'ignore',
        'browser.startup.page': 0,
        'datareporting.policy.dataSubmissionEnabled': False,
        # 'devtools.chrome.enabled': True,
        # 'devtools.debugger.remote-enabled': True,
        'extensions.autoDisableScopes': 10,
        'extensions.legacy.enabled': True,
        'identity.fxaccounts.autoconfig.uri': fxa_urls['content'],
        'testing.tps.skipPingValidation': True,
        'services.sync.log.appender.console': 'Trace',
        'services.sync.log.appender.dump': 'Trace',
        'services.sync.log.appender.file.level': 'Trace',
        'services.sync.log.appender.file.logOnSuccess': True,
        'services.sync.log.logger': 'Trace',
        'services.sync.log.logger.engine': 'Trace',
        'tps.config': json.dumps(tps_config),
        'tps.logfile': tps_log,
        'tps.seconds_since_epoch': int(time.time()),
        'xpinstall.signatures.required': False
    }
    profile = Profile(addons=[tps_addon], preferences=preferences)
    pytestconfig._profile = profile.profile
    yield profile


@pytest.fixture
def tps(firefox, firefox_log, monkeypatch, pytestconfig, tps_log, tps_profile):
    yield TPS(firefox, firefox_log, tps_log, tps_profile)


@pytest.fixture
def xcodebuild_log(pytestconfig, tmpdir):
    xcodebuild_log = str(tmpdir.join('xcodebuild.log'))
    pytestconfig._xcodebuild_log = xcodebuild_log
    yield xcodebuild_log


@pytest.fixture
def xcodebuild(fxa_account, monkeypatch, xcodebuild_log):
    monkeypatch.setenv('FXA_EMAIL', fxa_account.email)
    monkeypatch.setenv('FXA_PASSWORD', fxa_account.password)
    yield XCodeBuild(xcodebuild_log)


def pytest_addoption(parser):
    parser.addoption('--firefox', help='path to firefox binary (defaults to '
                     'downloading latest nightly build)')
    parser.addoption('--tps', help='path to tps add-on (defaults to '
                     'downloading latest nightly build)')


@pytest.mark.hookwrapper
def pytest_runtest_makereport(item, call):
    outcome = yield
    report = outcome.get_result()
    extra = getattr(report, 'extra', [])
    pytest_html = item.config.pluginmanager.getplugin('html')
    profile = getattr(item.config, '_profile', None)
    if profile is not None and os.path.exists(profile):
        # add sync logs to HTML report
        for root, _, files in os.walk(os.path.join(profile, 'weave', 'logs')):
            for f in files:
                path = os.path.join(root, f)
                if pytest_html is not None:
                    with io.open(path, 'r', encoding='utf8') as f:
                        extra.append(pytest_html.extras.text(f.read(), 'Sync'))
                report.sections.append(('Sync', 'Log: {}'.format(path)))
    for log in ('Firefox', 'TPS', 'XCodeBuild'):
        attr = '_{}_log'.format(log.lower())
        path = getattr(item.config, attr, None)
        if path is not None and os.path.exists(path):
            if pytest_html is not None:
                with io.open(path, 'r', encoding='utf8') as f:
                    extra.append(pytest_html.extras.text(f.read(), log))
            report.sections.append((log, 'Log: {}'.format(path)))
    report.extra = extra
