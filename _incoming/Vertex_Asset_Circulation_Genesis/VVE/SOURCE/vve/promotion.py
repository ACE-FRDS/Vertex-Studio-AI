from .domain import ChangeSet

class PromotionGate:
    def check(self,changeset:ChangeSet,simulation_passed:bool,human_approved:bool)->list[str]:
        errors=[]
        if changeset.real_repository_write:
            errors.append("VVE ChangeSet must not directly write Real Repository")
        if not simulation_passed:
            errors.append("simulation validation required")
        if not human_approved:
            errors.append("human approval required")
        return errors
