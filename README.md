# fhem-mirror
READ-ONLY mirror of the [main Subversion repository trunk](http://svn.fhem.de/fhem/trunk), updated daily.

## Branches
1. The [`master`](https://github.com/fhem/fhem-mirror/tree/master) branch hosts the current source code from [FHEM SVN Trunk](http://svn.fhem.de/fhem/trunk).
2. The [`travis`](https://github.com/fhem/fhem-mirror/tree/travis) branch is controlling the mirroring process, running on [Travis CI](https://travis-ci.com/).

## Pull requests
Any pull requests to any other branch besides [`travis`](https://github.com/fhem/fhem-mirror/tree/travis) will be rejected.
Please visit the official [FHEM support forum](https://forum.fhem.de/) to post your patches.

## Author matching
Authors from the Subversion repository will be referred here without any email relation.
Those that also have an Github.com account might have a different username here.

The [`authors.txt`](https://github.com/fhem/fhem-mirror/blob/travis/authors.txt) file will ensure to re-write authors from the Subversion repository to their Github.com username and email address.
Should an author want to be re-matched for any _future_ commits, s/he may modify [`authors.txt`](https://github.com/fhem/fhem-mirror/blob/travis/authors.txt) file and send a [Git pull request](https://help.github.com/articles/creating-a-pull-request-from-a-fork/).

Remember to fork the correct branch [`travis`](https://github.com/fhem/fhem-mirror/tree/travis), _not_ the [`master`](https://github.com/fhem/fhem-mirror/tree/master) branch.
