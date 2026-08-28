use std::collections::VecDeque;
#[derive(Debug,Clone,PartialEq,Eq)] pub struct Job{pub id:String,pub program:String}
#[derive(Default)] pub struct Scheduler{queue:VecDeque<Job>}
impl Scheduler{pub fn submit(&mut self,j:Job){self.queue.push_back(j)}pub fn next(&mut self)->Option<Job>{self.queue.pop_front()}pub fn len(&self)->usize{self.queue.len()}pub fn is_empty(&self)->bool{self.queue.is_empty()}}
