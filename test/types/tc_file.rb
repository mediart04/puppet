if __FILE__ == $0
    $:.unshift '..'
    $:.unshift '../../lib'
    $puppetbase = "../../../../language/trunk"
end

require 'puppet'
require 'test/unit'

# $Id$

class TestFile < Test::Unit::TestCase
    # hmmm
    # this is complicated, because we store references to the created
    # objects in a central store
    def setup
        @@tmpfiles = []
        @file = nil
        @path = File.join($puppetbase,"examples/root/etc/configfile")
        Puppet[:loglevel] = :debug if __FILE__ == $0
        Puppet[:statefile] = "/var/tmp/puppetstate"
        assert_nothing_raised() {
            @file = Puppet::Type::PFile.new(
                :name => @path
            )
        }
    end

    def teardown
        Puppet::Type.allclear
        @@tmpfiles.each { |file|
            system("rm -rf %s" % file)
        }
        system("rm -f %s" % Puppet[:statefile])
    end

    def initstorage
        Puppet::Storage.init
        Puppet::Storage.load
    end

    def clearstorage
        Puppet::Storage.store
        Puppet::Storage.clear
        initstorage()
    end

    def test_owner
        [Process.uid,%x{whoami}.chomp].each { |user|
            assert_nothing_raised() {
                @file[:owner] = user
            }
            assert_nothing_raised() {
                @file.evaluate
            }
            assert_nothing_raised() {
                @file.sync
            }
            assert_nothing_raised() {
                @file.evaluate
            }
            assert(@file.insync?())
        }
        assert_nothing_raised() {
            @file[:owner] = "root"
        }
        assert_nothing_raised() {
            @file.evaluate
        }
        # we might already be in sync
        assert(!@file.insync?())
        assert_nothing_raised() {
            @file.delete(:owner)
        }
    end

    def test_group
        [%x{groups}.chomp.split(/ /), Process.groups].flatten.each { |group|
            assert_nothing_raised() {
                @file[:group] = group
            }
            assert_nothing_raised() {
                @file.evaluate
            }
            assert_nothing_raised() {
                @file.sync
            }
            assert_nothing_raised() {
                @file.evaluate
            }
            assert(@file.insync?())
            assert_nothing_raised() {
                @file.delete(:group)
            }
        }
    end

    def test_create
        %w{a b c d}.collect { |name| "/tmp/createst%s" % name }.each { |path|
            file =nil
            assert_nothing_raised() {
                file = Puppet::Type::PFile.new(
                    :name => path,
                    :create => true
                )
            }
            assert_nothing_raised() {
                file.evaluate
            }
            assert_nothing_raised() {
                file.sync
            }
            assert_nothing_raised() {
                file.evaluate
            }
            assert(file.insync?())
            assert(FileTest.file?(path))
            @@tmpfiles.push path
        }
    end

    def test_create_dir
        %w{a b c d}.collect { |name| "/tmp/createst%s" % name }.each { |path|
            file = nil
            assert_nothing_raised() {
                file = Puppet::Type::PFile.new(
                    :name => path,
                    :create => "directory"
                )
            }
            assert_nothing_raised() {
                file.evaluate
            }
            assert_nothing_raised() {
                file.sync
            }
            assert_nothing_raised() {
                file.evaluate
            }
            assert(file.insync?())
            assert(FileTest.directory?(path))
            @@tmpfiles.push path
        }
    end

    def test_modes
        [0644,0755,0777,0641].each { |mode|
            assert_nothing_raised() {
                @file[:mode] = mode
            }
            assert_nothing_raised() {
                @file.evaluate
            }
            assert_nothing_raised() {
                @file.sync
            }
            assert_nothing_raised() {
                @file.evaluate
            }
            assert(@file.insync?())
            assert_nothing_raised() {
                @file.delete(:mode)
            }
        }
    end

    # just test normal links
    def test_normal_links
        link = "/tmp/puppetlink"
        assert_nothing_raised() {
            @file[:link] = link
        }
        # assert we got a fully qualified link
        assert(@file.state(:link).should =~ /^\//)

        # assert we aren't linking to ourselves
        assert(File.expand_path(@file.state(:link).link) !=
            File.expand_path(@file[:path]))

        # assert the should value does point to us
        assert_equal(File.expand_path(@file.state(:link).should),
            File.expand_path(@file[:path]))

        assert_nothing_raised() {
            @file.evaluate
        }
        assert_nothing_raised() {
            @file.sync
        }
        assert_nothing_raised() {
            @file.evaluate
        }
        assert(@file.insync?())
        assert_nothing_raised() {
            @file.delete(:link)
        }
        @@tmpfiles.push link
    end

    def test_checksums
        types = %w{md5 md5lite timestamp ctime}
        exists = "/tmp/sumtest-exists"
        nonexists = "/tmp/sumtest-nonexists"

        # try it both with files that exist and ones that don't
        files = [exists, nonexists]
        initstorage
        File.open(exists,"w") { |of|
            10.times { 
                of.puts rand(100)
            }
        }
        types.each { |type|
            files.each { |path|
                if Puppet[:debug]
                    Puppet.info "Testing %s on %s" % [type,path]
                end
                file = nil
                events = nil
                # okay, we now know that we have a file...
                assert_nothing_raised() {
                    file = Puppet::Type::PFile.new(
                        :name => path,
                        :create => true,
                        :checksum => type
                    )
                }
                assert_nothing_raised() {
                    file.evaluate
                }
                assert_nothing_raised() {
                    events = file.sync
                }
                # we don't want to kick off an event the first time we
                # come across a file
                assert(
                    ! events.include?(:file_modified)
                )
                assert_nothing_raised() {
                    File.open(path,"w") { |of|
                        10.times { 
                            of.puts rand(100)
                        }
                    }
                    #system("cat %s" % path)
                }
                Puppet::Type::PFile.clear
                # now recreate the file
                assert_nothing_raised() {
                    file = Puppet::Type::PFile.new(
                        :name => path,
                        :checksum => type
                    )
                }
                assert_nothing_raised() {
                    file.evaluate
                }
                assert_nothing_raised() {
                    events = file.sync
                }
                # verify that we're actually getting notified when a file changes
                assert(
                    events.include?(:file_modified)
                )
                assert_nothing_raised() {
                    Puppet::Type::PFile.clear
                }
                @@tmpfiles.push path
            }
        }
        # clean up so i don't screw up other tests
        Puppet::Storage.clear
    end

    def cyclefile(path)
        # i had problems with using :name instead of :path
        [:name,:path].each { |param|
            file = nil
            changes = nil
            comp = nil
            trans = nil

            initstorage
            assert_nothing_raised {
                file = Puppet::Type::PFile.new(
                    param => path,
                    :recurse => true,
                    :checksum => "md5"
                )
            }
            comp = Puppet::Component.new(
                :name => "component"
            )
            comp.push file
            assert_nothing_raised {
                trans = comp.evaluate
            }
            assert_nothing_raised {
                trans.evaluate
            }
            #assert_nothing_raised {
            #    file.sync
            #}
            clearstorage
            Puppet::Type.allclear
        }
    end

    def test_recursion
        path = "/tmp/filerecursetest"
        tmpfile = File.join(path,"testing")
        system("mkdir -p #{path}")
        cyclefile(path)
        File.open(tmpfile, File::WRONLY|File::CREAT|File::APPEND) { |of|
            of.puts "yayness"
        }
        cyclefile(path)
        File.open(tmpfile, File::WRONLY|File::APPEND) { |of|
            of.puts "goodness"
        }
        cyclefile(path)
        @@tmpfiles.push path
    end

    def test_simplelocalsource
        path = "/tmp/filesourcetest"
        system("mkdir -p #{path}")
        frompath = File.join(path,"source")
        topath = File.join(path,"dest")
        fromfile = nil
        tofile = nil
        trans = nil

        File.open(frompath, File::WRONLY|File::CREAT|File::APPEND) { |of|
            of.puts "yayness"
        }
        assert_nothing_raised {
            tofile = Puppet::Type::PFile.new(
                :name => topath,
                :source => frompath
            )
        }
        comp = Puppet::Component.new(
            :name => "component"
        )
        comp.push tofile
        assert_nothing_raised {
            trans = comp.evaluate
        }
        assert_nothing_raised {
            trans.evaluate
        }
        assert_nothing_raised {
            comp.sync
        }
        assert(FileTest.exists?(topath))
        from = File.open(frompath) { |o| o.read }
        to = File.open(topath) { |o| o.read }
        assert_equal(from,to)
        clearstorage
        Puppet::Type.allclear
        @@tmpfiles.push path
    end

    def test_xcomplicatedlocalsource
        path = "/tmp/complsourcetest"
        @@tmpfiles.push path
        system("mkdir -p #{path}")
        fromdir = File.join(path,"fromdir")
        frompath = File.join(fromdir,"source")
        todir = File.join(path,"todir")
        topath = File.join(todir,"source")
        fromfile = nil
        tofile = nil
        trans = nil

        Dir.mkdir(fromdir)
        File.open(frompath, File::WRONLY|File::CREAT|File::APPEND) { |of|
            of.puts "yayness"
        }

        assert_nothing_raised {
            tofile = Puppet::Type::PFile.new(
                :name => todir,
                :recurse => true,
                :source => fromdir
            )
        }
        comp = Puppet::Component.new(
            :name => "component"
        )
        comp.push tofile
        assert_nothing_raised {
            trans = comp.evaluate
        }
        assert_nothing_raised {
            trans.evaluate
        }
        assert(FileTest.file?(topath))
        from = File.open(frompath) { |o| o.read }
        to = File.open(topath) { |o| o.read }
        assert_equal(from,to)
        clearstorage
        Puppet::Type.allclear
    end
end
