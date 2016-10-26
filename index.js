var impromptu = require('impromptu')
var fs = require('fs')
var path = require('path')

// Helper function to format git statuses
var getStatuses = function (porcelainStatus) {
  var PORCELAIN_PROPERTY_REGEXES = {
    // Leading non-whitespace that is not a question mark
    staged: /^[^\?\s]/,
    // Trailing non-whitespace
    unstaged: /\S$/,
    // Any "A" or "??"
    added: /A|\?\?/,
    // Any "M"
    modified: /M/,
    // Any "D"
    deleted: /D/,
    // Any "R"
    renamed: /R/
  }

  return porcelainStatus.replace(/\s+$/, '').split('\0').map(function(line) {
    var status = line.substring(0, 2)
    var properties = []
    for (var property in PORCELAIN_PROPERTY_REGEXES) {
      if (PORCELAIN_PROPERTY_REGEXES[property].test(status)) properties.push(property)
    }

    return {
      path: line.slice(3),
      properties: properties
    }
  })
}

module.exports = impromptu.plugin.create(function(git) {
  // Helper to figure out if we're in a repo at all
  git.register('isRepo', {
    update: function(done) {
      var command = '([ -d .git ] || [[ "true" == `git rev-parse --is-inside-work-tree 2>&1` ]])'
      impromptu.exec(command, function(err) {
        done(err, !err)
      })
    }
  })

  // Root path to the repository
  git.register('root', {
    update: function(done) {
      var command = 'git rev-parse --show-toplevel 2>/dev/null'
      impromptu.exec(command, function(err, result) {
        if (err) {
          done(err, null)
        } else {
          done(err, result.trim())
        }
      })
    }
  })

  // Branch name
  // Returns commit hash when head is detached
  // Returns null in newly-initialized repos (note that isRepo() still returns true in this case)
  git.register('branch', {
    update: function(done) {
      var command = 'git rev-parse --abbrev-ref HEAD 2>/dev/null'
      impromptu.exec(command, function(err, result) {
        if (err) {
          done(err, null)
          return
        }

        result = result.trim()
        if (result !== 'HEAD') {
          done(err, result)
          return
        }

        impromptu.exec('git rev-parse --short HEAD', function(_err, _result) {
          done(_err, _result)
        })
      })
    }
  })

  // Short commit hash
  git.register('commit', {
    update: function(done) {
      impromptu.exec('git rev-parse --short HEAD 2>/dev/null', function(err, result) {
        if (err) {
          done(err, null)
        } else {
          done(err, result.trim())
        }
      })
    }
  })

  // Determine whether the repo is currently in a detached head state
  // This happens when you checkout, for example, a commit hash
  git.register('isDetachedHead', {
    update: function(done) {
      impromptu.exec('git symbolic-ref HEAD 2>/dev/null', function(err) {
        done(err, !!err)
      })
    }
  })

  // Whether the git repository is in the middle of a rebase.
  git.register('isRebasing', {
    update: function(done) {
      git.root(function(err, root) {
        if (err) {
          done(err)
          return
        }

        var command = "test -d " + root + "/.git/rebase-merge -o -d " + root + "/.git/rebase-apply"
        impromptu.exec(command, function(err) {
          if (!err) {
            done(null, true)
          } else if (err.code === 1) {
            done(null, false)
          } else {
            done(err, null)
          }
        })
      })
    }
  })

  // The remote branch name, if it exists
  git.register('remoteBranch', {
    update: function(done) {
      var trackingBranchCommand = "git rev-parse --abbrev-ref --symbolic-full-name @{u}"

      impromptu.exec(trackingBranchCommand, function(err, result) {
        if (result) {
          done(err, result.trim())
        } else {
          done(err, null)
        }
      })
    }
  })

  // Returns an object with 'ahead' and 'behind' keys
  // Each has a count of commits that your repo is ahead/behind its upstream
  //
  // This command *must* be passed through a formatter before its displayed
  git.register('_aheadBehind', {
    update: function(done) {
      git.fetch(function(err) {
        if (err) {
          done(err, null)
          return
        }

        git.remoteBranch(function(err, remoteBranch) {
          if (!remoteBranch) {
            done(err, null)
            return
          }

          var command = "git rev-list --left-right --count " + (remoteBranch.trim()) + "...HEAD"
          impromptu.exec(command, function(err, result) {
            if (err) {
              done(err, null)
              return
            }

            var data = result.trim().split(/\s+/).map(function(value) {
              return parseInt(value, 10)
            })

            done(err, {
              behind: data[0],
              ahead: data[1]
            })
          })
        })
      })
    }
  })

  // Get the number of commits you're ahead of the remote
  git.register('ahead', {
    update: function(done) {
      git._aheadBehind(function(err, aheadBehind) {
        done(err, aheadBehind != null ? aheadBehind.ahead : void 0)
      })
    }
  })

  // Get the number of commits you're behind the remote
  git.register('behind', {
    update: function(done) {
      git._aheadBehind(function(err, aheadBehind) {
        done(err, aheadBehind != null ? aheadBehind.behind : void 0)
      })
    }
  })

  var Statuses = function (statuses) {
    this.statuses = statuses

    var properties = ['added', 'modified', 'deleted', 'renamed', 'staged', 'unstaged']
    var property = null

    // Create status arrays.
    for (var i = 0; i < properties.length; i++) {
      this[properties[i]] = []
    }

    // Bind array formatters.
    for (property in Statuses.formatters) {
      if (this[property]) {
        this[property].toString = Statuses.formatters[property]
      }
    }

    // Populate status arrays.
    for (var j = 0; j < this.statuses.length; j++) {
      var status = this.statuses[j]

      for (var k = 0; k < properties.length; k++) {
        property = properties[k]
        if (status.properties.indexOf(property) > -1) {
          this[property].push(status)
        }
      }
    }
  }

  Statuses.prototype.toString = function() {
    var results = []
    if (this.modified.length) results.push(this.modified)
    if (this.added.length) results.push(this.added)
    if (this.deleted.length) results.push(this.deleted)
    if (this.renamed.length) results.push(this.renamed)
    return results.join(' ')
  }

  Statuses.formatters = {
    added: function() {
      return this.length ? '+' + this.length : ''
    },
    modified: function() {
      return this.length ? '∆' + this.length : ''
    },
    deleted: function() {
      return this.length ? '-' + this.length : ''
    },
    renamed: function() {
      return this.length ? '→' + this.length : ''
    }
  }

  // Returns an array of objects with 'path', 'code', 'staged', 'state'
  //
  // This command *must* be passed through a formatter before its displayed
  git.register('_status', {
    update: function(done) {
      impromptu.exec('git status --porcelain -z 2>/dev/null', function(err, result) {
        if (err) {
          done(err, null)
          return
        }

        var statuses = getStatuses(result)
        done(null, new Statuses(statuses))
      })
    }
  })

  // Register object and string methods for filtering the statuses.
  //
  // Object methods: `_staged`, `_unstaged`, `_added`, `_modified`, `_deleted`, `_renamed`
  // String methods: `staged`, `unstaged`, `added`, `modified`, `deleted`, `renamed`
  //
  // Strings are formatted as "∆2 +1 -3" by default.
  ;['staged', 'unstaged', 'added', 'modified', 'deleted', 'renamed'].forEach(function(type) {
    // Get an object that has filtered the statuses by type.
    git.register("_" + type, {
      update: function(done) {
        git._status(function(err, statuses) {
          done(err, new Statuses(statuses[type]))
        })
      }
    })

    // Get a string that represents the status.
    // Format: "∆2 +1 -3 →2"
    git.register(type, {
      update: function(done) {
        git["_" + type](function(err, statuses) {
          done(err, statuses.toString())
        })
      }
    })
  })

  // Fetch information about the repository
  git.register('fetch', {
    cache: 'repository',
    expire: 600,
    update: function(done) {
      git.isRepo(function(err, isRepo) {
        if (!isRepo) {
          done(err, isRepo)
          return
        }

        impromptu.exec('git fetch --all', function(err, results) {
          done(err, results)
        })
      })
    }
  })

  // Find the number of git stashes
  git.register('stashCount', {
    update: function(done) {
      git.root(function(err, root) {
        if (err) {
          done(err)
          return
        }

        fs.exists(path.join(root, '.git/logs/refs/stash'), function(exists) {
          if (!exists) {
            done(null, 0)
            return
          }

          impromptu.exec("wc -l " + (path.join(root, '.git/logs/refs/stash')), function(err, count) {
            done(err, parseInt(count.trim(), 10))
          })
        })
      })
    }
  })

  // Find the URL of the origin
  git.register('remoteUrl', {
    update: function(done) {
      impromptu.exec('git config --get remote.origin.url', done)
    }
  })

  // Register the 'git' repository type with impromptu
  impromptu.repository.register('git', {
    root: git.root,
    branch: git.branch,
    commit: git.commit
  })
})
