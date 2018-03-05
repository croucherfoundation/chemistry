require 'colorize'

# desc "Explaining what the task does"

namespace :chemistry do
  task :install => :environment do

    Rake::Task["chemistry:install:migrations"].invoke
    Rake::Task["chemistry:seed"].invoke

    # generate initializer if none

  end


  task :seed => :environment do
    section_types = JSON.parse(File.read(File.expand_path('../../../db/import/v1/section_types.json', __FILE__)))
    section_types.each do |st|
      begin
        if Chemistry::SectionType.find_by(slug: st['slug'])
          puts "- Section type #{st['slug']} exists".colorize(:light_white)
        else
          Chemistry::SectionType.create(st)
          puts "√ Section type: #{st['slug']} created".colorize(:green)
        end
      rescue => e
        puts "x Section type #{st['slug']} could not be created: #{e.message}".colorize(:red)
      end
    end

    templates = JSON.parse(File.read(File.expand_path('../../../db/import/v1/templates.json', __FILE__)))
    templates.each do |t|
      begin
        if Chemistry::Template.find_by(title: t['title'])
          puts "- Template #{t['title']} exists".colorize(:light_white)
        else
          section_types = t.delete('section_types')
          template = Chemistry::Template.create(t)
          template.section_types = section_types
          puts "√ Template: #{t['title']} created".colorize(:green)
        end
      rescue => e
        puts "x Template #{t['title']} could not be created: #{e.message}".colorize(:red)
      end
    end

  end

end

