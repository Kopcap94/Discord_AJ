module DiscordBot
  class Wiki
    include HTTParty

    def initialize( client )
      @c = client
      @bot = client.bot
      @channels = client.channels
      @config = client.config
      @thr = client.thr
      @names = [ 'recentchanges', 'wiki-activity', 'правки', 'активность', 'вики-активность' ]

      for_init
    end

    def commands
      @bot.command(
        :add_wiki,
        permission_level: 2,
        min_args: 1,
        description: "Добавляет вики в список патрулируемых и выводит правки в канал #recentchanges.",
        usage: "!add_wiki ru.community",
        permission_message: "Недостаточно прав, чтобы использовать эту команду."
      ) do | e, w | 
        begin
          add_wiki( e, w )
        rescue => err
          puts "[add_wiki]: #{ err }"
          e.respond "При попытке добавления произошла ошибка. Возможно, файл конфигурации сейчас перегружен. Попробуйте позднее."
        end
      end

      @bot.command(
        :attr_wiki,
        permission_level: 2,
        min_args: 2,
        description: "Изменяет переменную отображения загрузок (uploads), логов (logs) или ботов (bots).",
        usage: "!attr_wiki ru.community logs",
        permission_message: "Недостаточно прав, чтобы использовать эту команду."
      ) do | e, w, t | attr_wiki( e, w, t ) end
    end

    def for_init
      thr = []

      @thr[ 'wiki' ] = Thread.new {
        @config[ 'wikies' ].clone.each do | w, d |
          thr << Thread.new {
            begin
              get_data_from_api( w )
            rescue => err
              puts "#{ Time.now.strftime "[%Y-%m-%d %H:%M:%S]" } Error with wiki #{ w }"
              @c.error_log( err, "WIKI" )
            end
          }

        sleep 5
        end
 
        sleep 60

        thr.each { |t| t.join }
        for_init
      }
    end

    def get_data_from_api( w )
      d = JSON.parse(
        HTTParty.get(
          "http://#{ w }.wikia.com/api.php?action=query&list=recentchanges|groupmembers&rclimit=50&gmlimit=50&gmgroups=bot|bot-global&rcprop=user|title|timestamp|ids|comment|sizes|loginfo&format=json",
          :verify => false
        ).body,
        :symbolize_names => true
      )

      if d[ :query ].nil? or d[ :query ][ :recentchanges ].nil? then
        puts d
        return
      end

      bots = []
      d[ :users ].each do | bot |
        bots.push( bot[ :name ] )
      end

      d = d[ :query ][ :recentchanges ]
      data = @config[ 'wikies' ][ w ]
      rcid = data[ 'rcid' ]
      last_rcid = d[ 0 ][ :rcid ]

      if rcid == 0 then
        @config[ 'wikies' ][ w ][ 'rcid' ] = last_rcid
        @c.save_config
	local_variables.each { | var | eval( "#{ var } = nil" ) }
        return
      end

      if last_rcid <= rcid then
	local_variables.each { | var | eval( "#{ var } = nil" ) }
        return
      end

      @config[ 'wikies' ][ w ][ 'rcid' ] = last_rcid
      @c.save_config

      d.reverse.each do | obj |
        if( obj[ :rcid ] <= rcid ) or
          ( obj[ :revid ] == 0 and !data[ 'logs' ] ) or
          ( obj[ :type ] == 'log' and obj[ :logtype ] == 'upload' and !data[ 'uploads' ] ) or
          ( !data[ 'bots' ] and bots.include?( obj[ :user ] ) )
          next
        end

        emb = Discordrb::Webhooks::Embed.new

        if obj[ :type ] != 'log' then
          emb.color = "#507299"

          title = "[ #{ w } ] #{ obj[ :title ] }"
          if [ 110, 111, 1200, 1201, 1202, 2001, 2002 ].index( obj[ :ns ] ) then title = "[ #{ w } ] Тема на форуме или стене обсуждения" end

          emb.author = Discordrb::Webhooks::EmbedAuthor.new( name: title, url: "http://#{ w }.wikia.com/index.php?title=#{ obj[ :title ].gsub( /\s/, "_" ) }" )
          emb.title = "http://#{ w }.wikia.com/index.php?diff=#{ obj[ :revid ] }"
          emb.add_field( name: "Изменения:", value: "#{ obj[ :newlen ] - obj[ :oldlen ] } байт", inline: true )
        else
          emb.color = "#759B01"

          name = ""
          url = ""
          title = ""
          value = ""

          case obj[ :logtype ]
          when "wikifeatures"
            name = "WikiFeatures"
            url = "wikifeatures"
            title = "Опция"
            value = obj[ :comment ].gsub( /^[^:]+:/, '' ).to_s
          when "move"
            name = "переименования"
            url = "move"
            title = "Переименована страница"
            value = obj[ :title ]
          when "delete"
            name = "удаления"
            url = "delete"
            title = "#{ obj[ :logaction ] == 'delete' ? "Удалена" : "Восстановлена" } страница"
            value = obj[ :title ]
          when "protect"
            name = "защиты"
            url = "protect"
            title = obj[ :logaction ] == 'protect' ? "Защищена страница" : "Снята защита"
            value = obj[ :title ]
          when "block"
            name = "блокировок"
            url = "block"
            if obj[ :logaction ] == 'block' then
              title = "Заблокирован"
            elsif obj[ :logaction ] == 'reblock' then
              title = "Изменена блокировка"
            else
              title = "Разблокирован"
            end
            value = obj[ :title ].gsub( /^[^:]+:/, '' )
          when "upload"
            name = "загрузок"
            url = "upload"
            title = obj[ :logaction ] == 'upload' ? "Загружен файл" : "Перезаписан файл"
            value = obj[ :title ].gsub( /^[^:]+:/, '' )
          else
            puts "Отсутствует: #{ obj[ :logaction ] }"
            next
          end

          emb.author = Discordrb::Webhooks::EmbedAuthor.new( name: "[ #{ w } ] Лог #{ name }", url: "http://#{ w }.wikia.com/wiki/Special:Log/#{ url }" )
          emb.add_field( name: title, value: value, inline: true )

          # Blocks
          if obj[ :logaction ] == 'block' then
            emb.add_field( name: "Истекает", value: obj[ :block ][ :expiry ], inline: true )
          elsif obj[ :logaction ] == 'reblock' then
            emb.add_field( name: "Изменены условия", value: obj[ :"0" ], inline: true )
          end
        end

        emb.add_field( name: "Выполнил", value: obj[ :user ], inline: true )
        if obj[ :comment ].gsub( /^\s+/, '' ) != "" then
          comment = obj[ :comment ].gsub( /(@(here|everyone)|<[@!#$]?&?\d*>)/, '[ yolo ]' )
          emb.add_field( name: "Описание", value: "#{ comment[ 0..100 ] }" )
        end

        data[ 'servers' ].each do | id |
          if @channels[ id ].nil? then next; end

          s_ch = @channels[ id ].keys
          channel = s_ch & @names

          if channel.empty? then next; end
          @bot.send_message( @channels[ id ][ channel[ 0 ] ], '', false, emb )
        end

        sleep 1
      end

      local_variables.each { | var | eval( "#{ var } = nil" ) }
      sleep 1
    end

    def add_wiki( e, w )
      id = e.server.id
      w = w.gsub( /(http:\/\/|.wikia.com.*)/, '' )
      s_ch = @channels[ id ].keys

      if ( s_ch & @names ).empty? then
        e.respond "<@#{ e.user.id }>, на сервере отсутствует канал с одним из названий (#{ @names.join( ', ' ) }), чтобы публиковать туда данные о свежих правках с вики. Пожалуйста, создайте канал и попробуйте снова."
        return
      end

      if @config[ 'wikies' ][ w ].nil? then
        @config[ 'wikies' ][ w ] = { 
          'rcid' => 0,
          'uploads' => true,
          'logs' => true,
          'bots' => true,
          'servers' => [ id ]
        }
      elsif @config[ 'wikies' ][ w ][ 'servers' ].include?( id ) then
        e.respond "<@#{ e.user.id }>, #{ w } уже есть в списке для патрулирования на этом сервере."
        return
      else
        @config[ 'wikies' ][ w ][ 'servers' ].push( id )
      end

      @c.save_config

      e.respond "<@#{ e.user.id }>, #{ w } добавлен в список для патрулирования."
    end

    def attr_wiki( e, w, t )
      if @config[ 'wikies' ][ w ].nil? then
        e.respond "Такого вики-проекта не существует."
        return
      elsif ![ 'uploads', 'logs', 'bots' ].include?( t ) then
        e.respond "Таких параметров не существует. Предлагаемые параметры: uploads, logs, bots."
        return
      elsif !@config[ 'wikies' ][ w ][ 'servers' ].include?( e.server.id ) then
        e.respond "Недостаточно прав, чтобы изменять настройки для данной вики."
        return
      end

      s = @config[ 'wikies' ][ w ][ t ]
      @config[ 'wikies' ][ w ][ t ] = !s

      @c.save_config
      e.respond "Значение параметра #{ t } для вики #{ w } теперь #{ !s }."
    end
  end
end