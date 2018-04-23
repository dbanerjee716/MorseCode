IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[usp_MorseDecipher]') AND type in (N'P', N'PC'))
DROP PROCEDURE [dbo].[usp_MorseDecipher]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE procedure [dbo].[usp_MorseDecipher]
	@FilePath varchar(200),
	@FileName varchar(200)
AS
begin

	set nocount on
	
	declare @sql varchar(max)
	declare @MorseInput varchar(max)
	declare @MorseOutput varchar(max)
	declare @DelimiterPosition int
	declare @MorseLine varchar(max)
	declare @MorseInputId int

	-- Creating temporary tables
	
	create table #MorseMapping
	(AlphaValue char(1),
	MorseValue varchar(10))

	create table #MorseInput
	(MorseInputId int identity(1,1),
	MorseInput varchar(max))

	create table #MorseOutput
	(MorseOutputId int identity(1,1),
	MorseOutput varchar(max))
	
	-- Loading the Morse Code mapping and input files into temporary tables based on their 
	-- corresponding formats
	
	set @sql = 'insert into #MorseMapping
				select mm.*
				from openrowset
				(bulk ''' + @FilePath + '\MorseMap.txt'', formatfile=''' + @FilePath +'\MorseMappingFormat.fmt'') as mm'
	exec(@sql)
	
	set @sql = 'insert into #MorseInput
				select mci.*
				from openrowset
				(bulk ''' + @FilePath+'\' + @FileName + ''', formatfile=''' + @FilePath +'\MorseInputFormat.fmt'') as mci'
	exec(@sql)

	-- Collecting the letter and word 'break' points' into a temporary table called #Break;
	-- || being the letter breaks and |||| being the word breaks
	
	
	set @MorseInputId = 1

	while @MorseInputId <= (select COUNT(*) from #MorseInput)
	begin
		select @MorseLine = MorseInput
		from #MorseInput
		where MorseInputId = @MorseInputId
		
		declare @Pattern varchar(max)
		declare @NewPosition int
		declare @OldPosition int
		declare @LetterBreak int
		declare @StartPosition int
		declare @EndPosition int
		declare @WordBreak bit
		declare @MorseLetter varchar(max)

		create table #Break
		(BreakId int identity(1,1),
		BreakPosition int,
		WordBreak bit)

		set @Pattern = '||||'

		set @OldPosition=0
		set @NewPosition=charindex(@Pattern,@MorseLine) 

		while @NewPosition > 0 and @OldPosition<>@NewPosition
		 begin
		   insert into #Break Values (@NewPosition, 1)
		   Select @OldPosition=@NewPosition
		   select @NewPosition=charindex(@Pattern,Substring(@MorseLine,@NewPosition + 1,len(@MorseLine))) + @NewPosition
		end

		set @Pattern = '||'

		set @OldPosition=0
		set @NewPosition=charindex(@Pattern,@MorseLine) 

		while @NewPosition > 0 and @OldPosition<>@NewPosition
		 begin
		   insert into #Break Values (@NewPosition, 0)
		   Select @OldPosition=@NewPosition
		   select @NewPosition=charindex(@Pattern,Substring(@MorseLine,@NewPosition + 1,len(@MorseLine))) + @NewPosition
		end

		insert into #Break Values (datalength(@MorseLine) + 1, 0)

		declare CleanupCursor cursor for
		select BreakPosition
		from #Break
		where WordBreak = 1
		order by BreakPosition

		open CleanupCursor

		fetch next from CleanupCursor into @LetterBreak

		while @@fetch_status = 0
		begin
			delete from #Break
			where (BreakPosition = @LetterBreak
			and WordBreak = 0)
			or (BreakPosition > @LetterBreak
			and BreakPosition <= @LetterBreak + 2)

			fetch next from CleanupCursor into @LetterBreak
		end

		close CleanupCursor
		deallocate CleanupCursor

		-- Extracting the English translation of each letter in Morse Code using the mapping table
		-- for each line in the Morse Code input temporary table, accommodating for the word breaks
		
		set @StartPosition = 1
		set @EndPosition = 1
		set @MorseOutput = ''
		set @WordBreak = 0

		declare MorseOutputCursor cursor for 
		select BreakPosition, WordBreak
		from #Break
		order by BreakPosition

		open MorseOutputCursor

		fetch next from MorseOutputCursor into @EndPosition, @WordBreak

		while @@fetch_status = 0
		begin
			set @MorseLetter = substring(@MorseLine, @StartPosition, @EndPosition - @StartPosition)
			
			select @MorseOutput = @MorseOutput + AlphaValue
			from #MorseMapping
			where MorseValue = @MorseLetter

			if @WordBreak = 0
				set @StartPosition = @EndPosition + 2
			else
			begin
				set @StartPosition = @EndPosition + 4
				set @MorseOutput = @MorseOutput + ' '
			end
			fetch next from MorseOutputCursor into @EndPosition, @WordBreak
		end

		insert into #MorseOutput values (@MorseOutput)
		
		close MorseOutputCursor
		deallocate MorseOutputCursor

		drop table #Break

		set @MorseInputId = @MorseInputId + 1
	end

	select MorseOutput from #MorseOutput

	drop table #MorseOutput
	drop table #MorseInput
	drop table #MorseMapping
end
GO

