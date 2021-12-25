# fhem-mirror
READ-ONLY mirror of the [main Subversion repository trunk](http://svn.fhem.de/fhem/trunk), updated daily.

## Branches
1. The [`master`](https://github.com/fhem/fhem-mirror/tree/master) branch hosts the current source code from [FHEM SVN Trunk](http://svn.fhem.de/fhem/trunk).
2. The [`travis`](https://github.com/fhem/fhem-mirror/tree/travis) branch is controlling the mirroring process, running on [Github Actions](https://github.com/fhem/fhem-mirror/actions/workflows/mirror.yml).
3. Under [`tags`](https://github.com/fhem/fhem-mirror/tags) FHEM Releases are mirrored also.

## Pull requests
Pull requests to any other branch besides [`travis`](https://github.com/fhem/fhem-mirror/tree/travis) will be rejected.
Instead, a module may have its own repository here on [Github.com/fhem](https://www.github.com/fhem) and will accept your patch using a [pull request](https://help.github.com/en/articles/about-pull-requests).

If you can't find a repository for the module you would like to contribute, visit the official [FHEM support forum](https://forum.fhem.de/) to post your patch. However, it might not be very welcome as it easily mixes up with user support requests and makes version control extremely difficult to handle. For that particular reason, please consider contacting the maintainer using the forum direct message function and send a link to where s/he can find your changed version or patch file.

## Author matching
Authors from the Subversion repository will be referred here without any email relation.

Those that also have an Github.com account might have a different username here.

The [`authors.txt`](https://github.com/fhem/fhem-mirror/blob/travis/authors.txt) file will ensure to re-write authors from the Subversion repository to their Github.com username and email address.
Should an author want to be re-matched for any _future_ commits, s/he may modify [`authors.txt`](https://github.com/fhem/fhem-mirror/blob/travis/authors.txt) file and send a [Git pull request](https://help.github.com/articles/creating-a-pull-request-from-a-fork/).

For that purpose, remember to fork the correct branch [`travis`](https://github.com/fhem/fhem-mirror/tree/travis), _not_ the [`master`](https://github.com/fhem/fhem-mirror/tree/master) branch.
