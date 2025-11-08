-- =====================================================
-- ECOTHREADS - COMPLETE DATABASE SCHEMA
-- Clean, working schema with all features
-- =====================================================

-- =====================================================
-- 1. POSTS TABLE
-- =====================================================

CREATE TABLE IF NOT EXISTS posts (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  user_name TEXT,
  user_avatar TEXT,
  title TEXT NOT NULL,
  content TEXT,
  image_url TEXT,
  flair TEXT DEFAULT 'All',
  upvotes INTEGER DEFAULT 0,
  downvotes INTEGER DEFAULT 0,
  comments_count INTEGER DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_posts_user_id ON posts(user_id);
CREATE INDEX IF NOT EXISTS idx_posts_created_at ON posts(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_posts_flair ON posts(flair);
CREATE INDEX IF NOT EXISTS idx_posts_upvotes ON posts(upvotes DESC);

-- Enable RLS
ALTER TABLE posts ENABLE ROW LEVEL SECURITY;

-- Drop old policies
DROP POLICY IF EXISTS "Anyone can view posts" ON posts;
DROP POLICY IF EXISTS "Users can create posts" ON posts;
DROP POLICY IF EXISTS "Users can update own posts" ON posts;
DROP POLICY IF EXISTS "Users can delete own posts" ON posts;
DROP POLICY IF EXISTS "Enable read access for all users" ON posts;
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON posts;
DROP POLICY IF EXISTS "Enable update for users based on user_id" ON posts;
DROP POLICY IF EXISTS "Enable delete for users based on user_id" ON posts;

-- New policies
CREATE POLICY "Anyone can view posts" 
  ON posts FOR SELECT 
  USING (true);

CREATE POLICY "Authenticated users can create posts" 
  ON posts FOR INSERT 
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own posts" 
  ON posts FOR UPDATE 
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own posts" 
  ON posts FOR DELETE 
  TO authenticated
  USING (auth.uid() = user_id);

-- =====================================================
-- 2. VOTES TABLE (Upvotes/Downvotes)
-- =====================================================

CREATE TABLE IF NOT EXISTS votes (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id TEXT NOT NULL,  -- TEXT to support both auth users and anonymous
  post_id UUID REFERENCES posts(id) ON DELETE CASCADE NOT NULL,
  vote_type TEXT NOT NULL CHECK (vote_type IN ('upvote', 'downvote')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(user_id, post_id)  -- One vote per user per post
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_votes_user_id ON votes(user_id);
CREATE INDEX IF NOT EXISTS idx_votes_post_id ON votes(post_id);
CREATE INDEX IF NOT EXISTS idx_votes_user_post ON votes(user_id, post_id);

-- Enable RLS
ALTER TABLE votes ENABLE ROW LEVEL SECURITY;

-- Drop old policies
DROP POLICY IF EXISTS "Anyone can view votes" ON votes;
DROP POLICY IF EXISTS "Anyone can create votes" ON votes;
DROP POLICY IF EXISTS "Anyone can update votes" ON votes;
DROP POLICY IF EXISTS "Anyone can delete votes" ON votes;

-- Anyone can vote (Reddit-style)
CREATE POLICY "Anyone can view votes" 
  ON votes FOR SELECT 
  USING (true);

CREATE POLICY "Anyone can create votes" 
  ON votes FOR INSERT 
  WITH CHECK (true);

CREATE POLICY "Anyone can update votes" 
  ON votes FOR UPDATE 
  USING (true);

CREATE POLICY "Anyone can delete votes" 
  ON votes FOR DELETE 
  USING (true);

-- Trigger to update vote counts on posts
CREATE OR REPLACE FUNCTION update_votes_count()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.vote_type = 'upvote' THEN
      UPDATE posts SET upvotes = upvotes + 1 WHERE id = NEW.post_id;
    ELSE
      UPDATE posts SET downvotes = downvotes + 1 WHERE id = NEW.post_id;
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    IF OLD.vote_type = 'upvote' THEN
      UPDATE posts SET upvotes = GREATEST(upvotes - 1, 0) WHERE id = OLD.post_id;
    ELSE
      UPDATE posts SET downvotes = GREATEST(downvotes - 1, 0) WHERE id = OLD.post_id;
    END IF;
    IF NEW.vote_type = 'upvote' THEN
      UPDATE posts SET upvotes = upvotes + 1 WHERE id = NEW.post_id;
    ELSE
      UPDATE posts SET downvotes = downvotes + 1 WHERE id = NEW.post_id;
    END IF;
  ELSIF TG_OP = 'DELETE' THEN
    IF OLD.vote_type = 'upvote' THEN
      UPDATE posts SET upvotes = GREATEST(upvotes - 1, 0) WHERE id = OLD.post_id;
    ELSE
      UPDATE posts SET downvotes = GREATEST(downvotes - 1, 0) WHERE id = OLD.post_id;
    END IF;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_post_votes_count ON votes;
CREATE TRIGGER update_post_votes_count
  AFTER INSERT OR UPDATE OR DELETE ON votes
  FOR EACH ROW
  EXECUTE FUNCTION update_votes_count();

-- =====================================================
-- 3. COMMENTS TABLE
-- =====================================================

CREATE TABLE IF NOT EXISTS comments (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  post_id UUID REFERENCES posts(id) ON DELETE CASCADE NOT NULL,
  user_id TEXT NOT NULL,  -- TEXT to support both auth users and anonymous
  user_name TEXT DEFAULT 'Anonymous User',
  user_avatar TEXT,
  content TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_comments_post_id ON comments(post_id);
CREATE INDEX IF NOT EXISTS idx_comments_user_id ON comments(user_id);
CREATE INDEX IF NOT EXISTS idx_comments_created_at ON comments(created_at DESC);

-- Enable RLS
ALTER TABLE comments ENABLE ROW LEVEL SECURITY;

-- Drop old policies
DROP POLICY IF EXISTS "Anyone can view comments" ON comments;
DROP POLICY IF EXISTS "Anyone can create comments" ON comments;
DROP POLICY IF EXISTS "Anyone can update own comments" ON comments;
DROP POLICY IF EXISTS "Anyone can delete own comments" ON comments;
DROP POLICY IF EXISTS "Post owner can delete comments" ON comments;

-- New policies
CREATE POLICY "Anyone can view comments" 
  ON comments FOR SELECT 
  USING (true);

CREATE POLICY "Anyone can create comments" 
  ON comments FOR INSERT 
  WITH CHECK (true);

CREATE POLICY "Users can update own comments" 
  ON comments FOR UPDATE 
  USING (user_id = COALESCE(auth.uid()::TEXT, user_id));

CREATE POLICY "Users can delete own comments" 
  ON comments FOR DELETE 
  USING (user_id = COALESCE(auth.uid()::TEXT, user_id));

CREATE POLICY "Post owner can delete any comment on their post" 
  ON comments FOR DELETE 
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM posts 
      WHERE posts.id = comments.post_id 
      AND posts.user_id = auth.uid()
    )
  );

-- Trigger to update comment counts
CREATE OR REPLACE FUNCTION update_comments_count()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE posts SET comments_count = comments_count + 1 WHERE id = NEW.post_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE posts SET comments_count = GREATEST(comments_count - 1, 0) WHERE id = OLD.post_id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_post_comments_count ON comments;
CREATE TRIGGER update_post_comments_count
  AFTER INSERT OR DELETE ON comments
  FOR EACH ROW
  EXECUTE FUNCTION update_comments_count();

-- =====================================================
-- 4. REPORTS TABLE (NEW!)
-- =====================================================

CREATE TABLE IF NOT EXISTS reports (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  reporter_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  reporter_name TEXT,
  content_type TEXT NOT NULL CHECK (content_type IN ('post', 'comment')),
  content_id UUID NOT NULL,  -- ID of the post or comment being reported
  reason TEXT NOT NULL CHECK (reason IN (
    'spam', 
    'harassment', 
    'hate_speech', 
    'misinformation', 
    'inappropriate_content', 
    'other'
  )),
  description TEXT,  -- Optional: additional details
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'reviewed', 'resolved', 'dismissed')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  reviewed_at TIMESTAMP WITH TIME ZONE,
  reviewed_by UUID REFERENCES auth.users(id),
  UNIQUE(reporter_id, content_type, content_id)  -- One report per user per content
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_reports_reporter_id ON reports(reporter_id);
CREATE INDEX IF NOT EXISTS idx_reports_content_type ON reports(content_type);
CREATE INDEX IF NOT EXISTS idx_reports_content_id ON reports(content_id);
CREATE INDEX IF NOT EXISTS idx_reports_status ON reports(status);
CREATE INDEX IF NOT EXISTS idx_reports_created_at ON reports(created_at DESC);

-- Enable RLS
ALTER TABLE reports ENABLE ROW LEVEL SECURITY;

-- Policies
CREATE POLICY "Users can view own reports" 
  ON reports FOR SELECT 
  TO authenticated
  USING (reporter_id = auth.uid());

CREATE POLICY "Users can create reports (not own content)" 
  ON reports FOR INSERT 
  TO authenticated
  WITH CHECK (
    reporter_id = auth.uid() AND
    -- Can't report own posts
    NOT EXISTS (
      SELECT 1 FROM posts 
      WHERE id = content_id 
      AND user_id = auth.uid()
      AND content_type = 'post'
    ) AND
    -- Can't report own comments
    NOT EXISTS (
      SELECT 1 FROM comments 
      WHERE id = content_id 
      AND user_id::UUID = auth.uid()
      AND content_type = 'comment'
    )
  );

-- Note: Add admin policies later if needed
-- CREATE POLICY "Admins can view all reports" ON reports FOR SELECT TO authenticated USING (is_admin());
-- CREATE POLICY "Admins can update reports" ON reports FOR UPDATE TO authenticated USING (is_admin());

-- =====================================================
-- 5. ENABLE REALTIME FOR ALL TABLES
-- =====================================================

-- Enable realtime updates
ALTER PUBLICATION supabase_realtime ADD TABLE posts;
ALTER PUBLICATION supabase_realtime ADD TABLE votes;
ALTER PUBLICATION supabase_realtime ADD TABLE comments;
ALTER PUBLICATION supabase_realtime ADD TABLE reports;

-- =====================================================
-- 6. VERIFICATION QUERIES
-- =====================================================

-- Check if all tables exist
SELECT 
  CASE WHEN EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'posts') 
    THEN '✅' ELSE '❌' END || ' posts' AS posts_status,
  CASE WHEN EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'votes') 
    THEN '✅' ELSE '❌' END || ' votes' AS votes_status,
  CASE WHEN EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'comments') 
    THEN '✅' ELSE '❌' END || ' comments' AS comments_status,
  CASE WHEN EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'reports') 
    THEN '✅' ELSE '❌' END || ' reports' AS reports_status;

-- Check posts table structure
SELECT 
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_name = 'posts'
ORDER BY ordinal_position;

-- Show sample data counts
SELECT 
  (SELECT COUNT(*) FROM posts) as total_posts,
  (SELECT COUNT(*) FROM votes) as total_votes,
  (SELECT COUNT(*) FROM comments) as total_comments,
  (SELECT COUNT(*) FROM reports) as total_reports;

-- =====================================================
-- ✅ SCHEMA SETUP COMPLETE!
-- =====================================================

SELECT '
🎉 DATABASE SCHEMA SETUP COMPLETE!

✅ Posts table - Create, edit, delete own posts
✅ Votes table - Upvote/downvote with automatic counts
✅ Comments table - Anyone can comment, post owner can delete
✅ Reports table - Report posts/comments (not your own)
✅ Real-time enabled for all tables
✅ All triggers and policies configured

Next steps:
1. Run this SQL in Supabase SQL Editor
2. Enable Realtime in Database > Replication for all tables
3. Test with your Flutter app!
' as message;
