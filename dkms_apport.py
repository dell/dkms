#!/usr/bin/python
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

optparser = optparse.OptionParser('%prog [options]')
optparser.add_option('-m', help="Specify the DKMS module to find the package for",
                     action='store', type='string', dest='module')
optparser.add_option('-v', help="Specify the DKMS version to find the package for",
                     action='store', type='string', dest='version')
options=optparser.parse_args()[0]

if not options.module or not options.version:
    print >> sys.stderr, 'ERROR, both -m and -v are required'
    sys.exit(2)

package=packaging.get_file_package('/usr/src/' + options.module + '-' + options.version)
if package is None:
    print >> sys.stderr, 'ERROR: binary package for %s: %s not found' % (options.module,options.version)
    sys.exit(1)

make_log=os.path.join('/var','lib','dkms',options.module,options.version,'build','make.log')

report = apport.Report('Package')
report['Package'] = package
report['SourcePackage'] = apport.packaging.get_source(package)
report['ErrorMessage'] = "%s kernel module failed to build" % options.module
try:
    version = packaging.get_version(package)
except ValueError:
    version = 'N/A'
if version is None:
    version = 'N/A'
report['PackageVersion'] = version
attach_file_if_exists(report, make_log, 'DKMSBuildLog')
report.write(open(apport.fileutils.make_report_path(report), 'w'))

