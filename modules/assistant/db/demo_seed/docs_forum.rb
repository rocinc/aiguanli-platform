# frozen_string_literal: true

module DemoSeed
  module DocsForum
    private

    def forum
      tech = project.forums.find_by!(name: "技术讨论")
      Message.where(forum: tech, parent_id: nil).find_each { |topic| remember_message(topic.subject, topic.id) }

      feedback = ensure_forum("用户反馈", "客户和内测用户的原话，由团队成员转述，并在下面跟进。", 1)
      ideas = ensure_forum("产品想法", "还没有排期的想法，一个想法一个主题。结论只有三种：做、不做、再等等。", 3)
      tech.update_columns(position: 2)

      post_all(feedback, feedback_topics)
      post_all(tech, tech_topics)
      post_all(ideas, idea_topics)
      [feedback, tech, ideas].each { |board| Forum.reset_counters!(board.id) }
      say("forum topics=#{Message.where(forum: [feedback, tech, ideas], parent_id: nil).count} replies=#{Message.where(forum: [feedback, tech, ideas]).where.not(parent_id: nil).count}")
    end

    def ensure_forum(name, description, position)
      Forum.find_by(project:, name:) || Forum.create!(project:, name:, description:, position:)
    end

    def post_all(board, topics)
      topics.each do |topic|
        root = post(board, topic[:by], topic[:at], topic[:subject], topic[:body])
        remember_message(topic[:subject], root.id)
        last = root.created_at
        topic[:replies].each do |by, at, body|
          reply = post(board, by, at, "回复：#{topic[:subject]}", body, parent: root)
          last = reply.created_at
        end
        root.update_columns(updated_at: last)
      end
    end

    def post(board, key, (day, hm), subject, body, parent: nil)
      stamp = t(day, hm)
      message = as(key) do
        Message.create!(forum: board, parent:, author: user(key), subject:, content: fmt(body), created_at: stamp, updated_at: stamp)
      end
      message.update_columns(created_at: stamp, updated_at: stamp)
      message
    end
  end
end
