# frozen_string_literal: true

module GitHubChangelogGenerator
  class Generator
    # Main function to start change log generation
    #
    # @return [String] Generated change log file
    def compound_changelog
      fetch_and_filter_tags
      fetch_issues_and_pr

      log = ""
      log += options[:frontmatter] if options[:frontmatter]
      log += "#{options[:header]}\n\n"

      log += if options[:unreleased_only]
               generate_log_between_tags(filtered_tags[0], nil)
             else
               generate_log_for_all_tags
             end

      log += File.read(options[:base]) if File.file?(options[:base])

      credit_line = "\n\n\\* *This Change Log was automatically generated by [github_changelog_generator](https://github.com/skywinder/Github-Changelog-Generator)*"
      log.gsub!(credit_line, "") # Remove old credit lines
      log += credit_line
    
      @log = log
    end

    # @param [Array] issues List of issues on sub-section
    # @param [String] prefix Name of sub-section
    # @return [String] Generate ready-to-go sub-section
    def generate_sub_section(issues, prefix)
      log = ""

      if issues.any?
        log += "#{prefix}\n\n" unless options[:simple_list]
        issues.each do |issue|
          merge_string = get_string_for_issue(issue)
          log += "- #{merge_string}\n"
        end
        log += "\n"
      end
      log
    end

    # It generate one header for section with specific parameters.
    #
    # @param [String] newer_tag_name - name of newer tag
    # @param [String] newer_tag_link - used for links. Could be same as #newer_tag_name or some specific value, like HEAD
    # @param [Time] newer_tag_time - time, when newer tag created
    # @param [String] older_tag_link - tag name, used for links.
    # @param [String] project_url - url for current project.
    # @return [String] - Generate one ready-to-add section.
    def generate_header(newer_tag_name, newer_tag_link, newer_tag_time, older_tag_link, project_url)
      log = ""

      # Generate date string:
      time_string = newer_tag_time.strftime(options[:date_format])

      # Generate tag name and link
      release_url = if options[:release_url]
                      format(options[:release_url], newer_tag_link)
                    else
                      "#{project_url}/tree/#{newer_tag_link}"
                    end
      log += if newer_tag_name.equal?(options[:unreleased_label])
               "## [#{newer_tag_name}](#{release_url})\n\n"
             else
               "## [#{newer_tag_name}](#{release_url}) (#{time_string})\n"
             end

      if options[:compare_link] && older_tag_link
        # Generate compare link
        log += "[Full Changelog](#{project_url}/compare/#{older_tag_link}...#{newer_tag_link})\n\n"
      end

      log
    end

    # Generate log only between 2 specified tags
    # @param [String] older_tag all issues before this tag date will be excluded. May be nil, if it's first tag
    # @param [String] newer_tag all issue after this tag will be excluded. May be nil for unreleased section
    def generate_log_between_tags(older_tag, newer_tag)
      filtered_issues, filtered_pull_requests = filter_issues_for_tags(newer_tag, older_tag)

      older_tag_name = older_tag.nil? ? detect_since_tag : older_tag["name"]

      if newer_tag.nil? && filtered_issues.empty? && filtered_pull_requests.empty?
        # do not generate empty unreleased section
        return ""
      end

      create_log_for_tag(filtered_pull_requests, filtered_issues, newer_tag, older_tag_name)
    end

    # Apply all filters to issues and pull requests
    #
    # @return [Array] filtered issues and pull requests
    def filter_issues_for_tags(newer_tag, older_tag)
      filtered_pull_requests = delete_by_time(@pull_requests, "actual_date", older_tag, newer_tag)
      filtered_issues        = delete_by_time(@issues, "actual_date", older_tag, newer_tag)

      newer_tag_name = newer_tag.nil? ? nil : newer_tag["name"]

      if options[:filter_issues_by_milestone]
        # delete excess irrelevant issues (according milestones). Issue #22.
        filtered_issues = filter_by_milestone(filtered_issues, newer_tag_name, @issues)
        filtered_pull_requests = filter_by_milestone(filtered_pull_requests, newer_tag_name, @pull_requests)
      end
      [filtered_issues, filtered_pull_requests]
    end

    # The full cycle of generation for whole project
    # @return [String] The complete change log
    def generate_log_for_all_tags
      puts "Generating log..." if options[:verbose]

      log = generate_unreleased_section

      @tag_section_mapping.each_pair do |_tag_section, left_right_tags|
        older_tag, newer_tag = left_right_tags
        log += generate_log_between_tags(older_tag, newer_tag)
      end

      log
    end

    def generate_unreleased_section
      log = ""
      if options[:unreleased]
        start_tag      = filtered_tags[0] || sorted_tags.last
        unreleased_log = generate_log_between_tags(start_tag, nil)
        log           += unreleased_log if unreleased_log
      end
      log
    end

    # Parse issue and generate single line formatted issue line.
    #
    # Example output:
    # - Add coveralls integration [\#223](https://github.com/skywinder/github-changelog-generator/pull/223) (@skywinder)
    #
    # @param [Hash] issue Fetched issue from GitHub
    # @return [String] Markdown-formatted single issue
    def get_string_for_issue(issue)
      encapsulated_title = encapsulate_string issue["title"]

      title_with_number = "#{encapsulated_title} [\\##{issue['number']}](#{issue['html_url']})"
      if options[:issue_line_labels].present?
        title_with_number = "#{title_with_number}#{line_labels_for(issue)}"
      end
      issue_line_with_user(title_with_number, issue)
    end

    private

    def line_labels_for(issue)
      labels = if options[:issue_line_labels] == ["ALL"]
                 issue["labels"]
               else
                 issue["labels"].select { |label| options[:issue_line_labels].include?(label["name"]) }
               end
      labels.map { |label| " \[[#{label['name']}](#{label['url'].sub('api.github.com/repos', 'github.com')})\]" }.join("")
    end

    def issue_line_with_user(line, issue)
      return line if !options[:author] || issue["pull_request"].nil?

      user = issue["user"]
      return "#{line} ({Null user})" unless user

      if options[:usernames_as_github_logins]
        "#{line} (@#{user['login']})"
      else
        "#{line} ([#{user['login']}](#{user['html_url']}))"
      end
    end
  end
end
