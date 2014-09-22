#!/usr/bin/python3
#
#  Dynamic Kernel Module Support (DKMS) <dkms-devel@dell.com>
#  Copyright (C) 2009 Dell, Inc.
#  by Mario Limonciello
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#

import apport
from apport.hookutils import *
import sys
import subprocess, optparse

from datetime import datetime

optparser = optparse.OptionParser('%prog [options]')
optparser.add_option('-m', help="Specify the DKMS module to find the package for",
                     action='store', type='string', dest='module')
optparser.add_option('-v', help="Specify the DKMS version to find the package for",
                     action='store', type='string', dest='version')
optparser.add_option('-k', help="Specify the kernel version",
                     action='store', type='string', dest='kernel')
options=optparser.parse_args()[0]

if not options.module or not options.version:
    sys.stderr.write('ERROR (dkms apport): both -m and -v are required\n')
    sys.exit(2)

package=packaging.get_file_package('/usr/src/' + options.module + '-' + options.version)
if package is None:
    sys.stderr.write('ERROR (dkms apport): binary package for %s: %s not found\n' % (options.module,options.version))
    sys.exit(1)

if options.kernel:
    # TODO: Ubuntu specific
    kernel_package = "linux-headers-" + options.kernel

    supported_kernel = True
    try:
        supported_kernel = apport.packaging.is_distro_package(kernel_package)
    except ValueError as e:
        if str(e) == 'package does not exist':
            supported_kernel = False

    if not supported_kernel:
        sys.stderr.write('ERROR (dkms apport): kernel package %s is not supported\n' % (kernel_package))
        sys.exit(1)

make_log=os.path.join('/var','lib','dkms',options.module,options.version,'build','make.log')

report = apport.Report('Package')
report['Package'] = package
try:
    report['SourcePackage'] = apport.packaging.get_source(package)
except ValueError:
    sys.stderr.write('ERROR (dkms apport): unable to determine source package for %s\n' % package)
    sys.exit(3)
try:
    version = packaging.get_version(package)
except ValueError:
    version = '(not installed)'
if version is None:
    version = '(not installed)'

if report['SourcePackage'] == 'fglrx-installer':
    fglrx_make_log = os.path.join('/var','lib','dkms',options.module,options.version,'build','make.sh.log')
    attach_file_if_exists(report, fglrx_make_log, 'FglrxBuildLog')

report['PackageVersion'] = version
report['Title'] = "%s %s: %s kernel module failed to build" % (package, version, options.module)
attach_file_if_exists(report, make_log, 'DKMSBuildLog')
if 'DKMSBuildLog' in report:
    this_year = str(datetime.today().year)
    if 'Segmentation fault' in report['DKMSBuildLog']:
        sys.stderr.write('ERROR (dkms apport): There was a segmentation fault when trying to build the module\n')
        sys.exit(1)
    for line in report['DKMSBuildLog'].split('\n'):
        if ': error:' in line:
            report['DuplicateSignature'] = 'dkms:%s:%s:%s' % (package, version, line.strip())
            break

if options.kernel:
    report['DKMSKernelVersion'] = options.kernel
with open(apport.fileutils.make_report_path(report), 'wb') as f:
    report.write(f)
